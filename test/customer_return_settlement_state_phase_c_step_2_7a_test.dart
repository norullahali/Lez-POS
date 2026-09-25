import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertCustomer() => db.into(db.customers).insert(
        const CustomersCompanion(name: Value('Test Customer')),
      );

  Future<int> insertReturn({double total = 100, int? originalInvoiceId}) =>
      db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              returnNumber:
                  Value('RET-${DateTime.now().microsecondsSinceEpoch}'),
              total: Value(total),
              originalInvoiceId: originalInvoiceId == null
                  ? const Value.absent()
                  : Value(originalInvoiceId),
            ),
          );

  Future<void> insertRefund({
    required int customerId,
    required double amount,
    int? referenceId,
  }) async {
    await db.into(db.customerTransactions).insert(
          CustomerTransactionsCompanion(
            customerId: Value(customerId),
            type: const Value('REFUND'),
            amount: Value(amount),
            referenceId:
                referenceId == null ? const Value.absent() : Value(referenceId),
          ),
        );
  }

  Future<void> runV32Backfill(AppDatabase database) async {
    await database.customStatement(
      '''
      UPDATE customer_returns
      SET settled_amount = COALESCE((
        SELECT SUM(ct.amount)
        FROM customer_transactions ct
        WHERE ct.type = 'REFUND'
          AND ct.reference_id = customer_returns.id
          AND ct.amount > 0
      ), 0)
      ''',
    );
  }

  Future<AppDatabase> openDatabaseMigratedFromV31({
    required int customerId,
    required List<Map<String, dynamic>> returns,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final rawDb = sqlite3.sqlite3.openInMemory();

    rawDb.execute('''
      CREATE TABLE customers (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT 0,
        credit_limit REAL NOT NULL DEFAULT 0,
        loyalty_points REAL NOT NULL DEFAULT 0
      );
    ''');

    rawDb.execute('''
      CREATE TABLE customer_returns (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        original_invoice_id INTEGER,
        return_number TEXT NOT NULL,
        return_date INTEGER NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        reason TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      );
    ''');

    rawDb.execute('''
      CREATE TABLE customer_transactions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL REFERENCES customers(id),
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        reference_id INTEGER,
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL DEFAULT 0
      );
    ''');

    rawDb.execute(
      "INSERT INTO customers (id, name) VALUES (?, ?);",
      [customerId, 'Migration Customer'],
    );

    for (final row in returns) {
      rawDb.execute(
        '''
        INSERT INTO customer_returns
          (id, original_invoice_id, return_number, return_date, total, reason, notes)
        VALUES (?, ?, ?, ?, ?, '', '');
        ''',
        [
          row['id'],
          row['originalInvoiceId'],
          row['returnNumber'],
          DateTime.now().millisecondsSinceEpoch,
          row['total'],
        ],
      );
    }

    for (final row in transactions) {
      rawDb.execute(
        '''
        INSERT INTO customer_transactions
          (customer_id, type, amount, reference_id, note, created_at)
        VALUES (?, ?, ?, ?, '', 0);
        ''',
        [
          row['customerId'],
          row['type'],
          row['amount'],
          row['referenceId'],
        ],
      );
    }

    rawDb.userVersion = 31;

    return AppDatabase.test(NativeDatabase.opened(rawDb));
  }

  group('Phase C Step 2.7A customer return settlement state', () {
    test('A) schema version is 33', () {
      expect(db.schemaVersion, 34);
    });

    test('B) new customer_returns rows default settled_amount = 0', () async {
      final returnId = await insertReturn();
      final header = await db.returnsDao.getCustomerReturnById(returnId);
      expect(header, isNotNull);
      expect(header!.settledAmount, 0);
    });

    test('C) DAO reads settled_amount correctly', () async {
      final returnId = await insertReturn();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 25 WHERE id = ?',
        [returnId],
      );

      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        25,
      );
      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(999999),
        isNull,
      );
    });

    test('D) conditional increment succeeds within cap', () async {
      final returnId = await insertReturn();
      final ok = await db
          .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                returnId: returnId,
                amount: 30,
                creditCap: 100,
              ));
      expect(ok, isTrue);
      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        30,
      );
    });

    test('E) conditional increment fails above cap', () async {
      final returnId = await insertReturn();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 80 WHERE id = ?',
        [returnId],
      );

      final ok = await db
          .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                returnId: returnId,
                amount: 30,
                creditCap: 100,
              ));
      expect(ok, isFalse);
      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        80,
      );
    });

    test('F) failed increment does not modify settled_amount', () async {
      final returnId = await insertReturn();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 10 WHERE id = ?',
        [returnId],
      );

      await db
          .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                returnId: returnId,
                amount: 5,
                creditCap: 12,
              ));

      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        10,
      );
    });

    test('G) successful increment modifies settled_amount exactly once',
        () async {
      final returnId = await insertReturn();
      final ok = await db
          .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                returnId: returnId,
                amount: 15,
                creditCap: 15,
              ));
      expect(ok, isTrue);
      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        15,
      );
    });

    test('H) multiple successful increments accumulate', () async {
      final returnId = await insertReturn();

      expect(
        await db
            .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                  returnId: returnId,
                  amount: 20,
                  creditCap: 100,
                )),
        isTrue,
      );
      expect(
        await db
            .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                  returnId: returnId,
                  amount: 30,
                  creditCap: 100,
                )),
        isTrue,
      );

      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        50,
      );
    });

    test('I) multiple customer_returns have independent settled_amount',
        () async {
      final returnA = await insertReturn(total: 40);
      final returnB = await insertReturn(total: 60);

      expect(
        await db
            .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                  returnId: returnA,
                  amount: 10,
                  creditCap: 20,
                )),
        isTrue,
      );
      expect(
        await db
            .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                  returnId: returnB,
                  amount: 25,
                  creditCap: 25,
                )),
        isTrue,
      );

      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnA),
        10,
      );
      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnB),
        25,
      );
    });

    test('J) migration backfill: one linked REFUND populates settled_amount',
        () async {
      const customerId = 1;
      final migrated = await openDatabaseMigratedFromV31(
        customerId: customerId,
        returns: [
          {
            'id': 1,
            'originalInvoiceId': null,
            'returnNumber': 'RET-1',
            'total': 100,
          },
        ],
        transactions: [
          {
            'customerId': customerId,
            'type': 'REFUND',
            'amount': 40,
            'referenceId': 1,
          },
        ],
      );
      addTearDown(migrated.close);

      final header = await migrated.returnsDao.getCustomerReturnById(1);
      expect(header!.settledAmount, 40);
    });

    test('K) migration backfill: multiple linked REFUNDs are summed', () async {
      const customerId = 1;
      final migrated = await openDatabaseMigratedFromV31(
        customerId: customerId,
        returns: [
          {
            'id': 2,
            'originalInvoiceId': null,
            'returnNumber': 'RET-2',
            'total': 100,
          },
        ],
        transactions: [
          {
            'customerId': customerId,
            'type': 'REFUND',
            'amount': 15,
            'referenceId': 2,
          },
          {
            'customerId': customerId,
            'type': 'REFUND',
            'amount': 25,
            'referenceId': 2,
          },
        ],
      );
      addTearDown(migrated.close);

      final header = await migrated.returnsDao.getCustomerReturnById(2);
      expect(header!.settledAmount, 40);
    });

    test('L) migration backfill ignores RETURN transactions', () async {
      const customerId = 1;
      final migrated = await openDatabaseMigratedFromV31(
        customerId: customerId,
        returns: [
          {
            'id': 3,
            'originalInvoiceId': null,
            'returnNumber': 'RET-3',
            'total': 100,
          },
        ],
        transactions: [
          {
            'customerId': customerId,
            'type': 'RETURN',
            'amount': -100,
            'referenceId': 3,
          },
          {
            'customerId': customerId,
            'type': 'REFUND',
            'amount': 20,
            'referenceId': 3,
          },
        ],
      );
      addTearDown(migrated.close);

      final header = await migrated.returnsDao.getCustomerReturnById(3);
      expect(header!.settledAmount, 20);
    });

    test('M) migration backfill ignores REFUND with null reference_id',
        () async {
      const customerId = 1;
      final migrated = await openDatabaseMigratedFromV31(
        customerId: customerId,
        returns: [
          {
            'id': 4,
            'originalInvoiceId': null,
            'returnNumber': 'RET-4',
            'total': 100,
          },
        ],
        transactions: [
          {
            'customerId': customerId,
            'type': 'REFUND',
            'amount': 50,
            'referenceId': null,
          },
        ],
      );
      addTearDown(migrated.close);

      final header = await migrated.returnsDao.getCustomerReturnById(4);
      expect(header!.settledAmount, 0);
    });

    test('N) migration backfill counts only REFUNDs for the matching return',
        () async {
      const customerId = 1;
      final migrated = await openDatabaseMigratedFromV31(
        customerId: customerId,
        returns: [
          {
            'id': 5,
            'originalInvoiceId': null,
            'returnNumber': 'RET-5A',
            'total': 50,
          },
          {
            'id': 6,
            'originalInvoiceId': null,
            'returnNumber': 'RET-5B',
            'total': 70,
          },
        ],
        transactions: [
          {
            'customerId': customerId,
            'type': 'REFUND',
            'amount': 10,
            'referenceId': 5,
          },
          {
            'customerId': customerId,
            'type': 'REFUND',
            'amount': 99,
            'referenceId': 6,
          },
        ],
      );
      addTearDown(migrated.close);

      expect(
        (await migrated.returnsDao.getCustomerReturnById(5))!.settledAmount,
        10,
      );
      expect(
        (await migrated.returnsDao.getCustomerReturnById(6))!.settledAmount,
        99,
      );
    });

    test('O) return with no REFUND defaults to zero', () async {
      const customerId = 1;
      final migrated = await openDatabaseMigratedFromV31(
        customerId: customerId,
        returns: [
          {
            'id': 7,
            'originalInvoiceId': null,
            'returnNumber': 'RET-7',
            'total': 100,
          },
        ],
        transactions: const [],
      );
      addTearDown(migrated.close);

      final header = await migrated.returnsDao.getCustomerReturnById(7);
      expect(header!.settledAmount, 0);
    });

    test('P) settled_amount may exceed customer_returns.total', () async {
      final customerId = await insertCustomer();
      final returnId = await insertReturn(total: 40);
      await insertRefund(
        customerId: customerId,
        amount: 50,
        referenceId: returnId,
      );
      await runV32Backfill(db);

      final header = await db.returnsDao.getCustomerReturnById(returnId);
      expect(header!.total, 40);
      expect(header.settledAmount, 50);
      expect(header.settledAmount, greaterThan(header.total));
    });

    test('Q) conditional increment does not create REFUND transactions',
        () async {
      final returnId = await insertReturn();
      final before = await db.select(db.customerTransactions).get();

      await db
          .transaction(() => db.returnsDao.incrementSettledAmountIfWithinCap(
                returnId: returnId,
                amount: 10,
                creditCap: 10,
              ));

      final after = await db.select(db.customerTransactions).get();
      expect(after.length, before.length);
    });

    test('backfill helper ignores non-positive REFUND amounts', () async {
      final customerId = await insertCustomer();
      final returnId = await insertReturn();
      await insertRefund(
        customerId: customerId,
        amount: 30,
        referenceId: returnId,
      );
      await db.into(db.customerTransactions).insert(
            CustomerTransactionsCompanion(
              customerId: Value(customerId),
              type: const Value('REFUND'),
              amount: const Value(-5),
              referenceId: Value(returnId),
            ),
          );
      await runV32Backfill(db);

      expect(
        await db.returnsDao.getSettledAmountForCustomerReturn(returnId),
        30,
      );
    });
  });
}
