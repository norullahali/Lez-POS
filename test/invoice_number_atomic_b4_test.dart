import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/credit_limit_exception.dart';
import 'package:lez_pos/core/services/invoice_number_service.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/stock_guard.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite3/sqlite3.dart' show Database, SqliteException;
import 'package:uuid/uuid.dart';

const _b4TestUuid = Uuid();
String b4IdempotencyKey() => _b4TestUuid.v4();
const b4Fingerprint = 'b4-test-fingerprint';

/// Bootstraps a full schema, then removes v36-only artifacts and sets user_version=35.
///
/// Uses a temp file because closing the bootstrap [AppDatabase] can release the
/// sole handle to an in-memory database and drop all tables.
Future<({Database rawDb, String path})> openSimulatedV35RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b4_v35_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  // Force Drift to run onCreate before downgrading to v35.
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
    'DROP TABLE IF EXISTS sales_invoice_daily_sequences',
  );
  await bootstrap.customStatement(
    'DROP INDEX IF EXISTS uq_sales_invoices_invoice_number',
  );
  await bootstrap.customStatement('PRAGMA user_version = 35');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 35);
  return (rawDb: rawDb, path: dbPath);
}

void insertLegacySalesInvoice(Database rawDb, String invoiceNumber) {
  rawDb.execute(
    '''
    INSERT INTO sales_invoices (
      invoice_number, subtotal, total, payment_method, cash_paid, debt_amount
    ) VALUES (?, 10, 10, 'CASH', 10, 0);
    ''',
    [invoiceNumber],
  );
}

Future<List<String>> legacyInvoiceNumbers(Database rawDb) async {
  final rows = rawDb.select(
    'SELECT invoice_number FROM sales_invoices ORDER BY invoice_number, id',
  );
  return rows.map((r) => r['invoice_number'] as String).toList();
}

void main() {
  late AppDatabase db;
  late PosSaleService saleService;
  late int productId;

  setUp(() async {
    db = AppDatabase.test();
    saleService = PosSaleService(db);
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B4 Product'),
            barcode: Value('B4-PROD-1'),
            currentStock: Value(100),
            costPrice: Value(5),
            sellPrice: Value(10),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  SalesInvoicesCompanion cashSaleHeader({double amount = 10}) {
    return SalesInvoicesCompanion(
      subtotal: Value(amount),
      total: Value(amount),
      paymentMethod: const Value('CASH'),
      cashPaid: Value(amount),
      debtAmount: const Value(0),
    );
  }

  List<SaleItemsCompanion> cashSaleItems({double qty = 1, double price = 10}) {
    return [
      SaleItemsCompanion(
        productId: Value(productId),
        quantity: Value(qty),
        unitPrice: Value(price),
        unitCost: const Value(5),
        total: Value(qty * price),
      ),
    ];
  }

  Future<String> runCashSaleWithRetry(
    PosSaleService service, {
    double amount = 10,
    double qty = 1,
    int? saleProductId,
    int maxAttempts = 20,
  }) async {
    final targetProductId = saleProductId ?? productId;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final result = await service.processSale(
          idempotencyKey: b4IdempotencyKey(),
          fingerprintHash: b4Fingerprint,
          invoice: cashSaleHeader(amount: amount),
          items: [
            SaleItemsCompanion(
              productId: Value(targetProductId),
              quantity: Value(qty),
              unitPrice: Value(amount / qty),
              unitCost: const Value(5),
              total: Value(amount),
            ),
          ],
          debtAmount: 0,
          netSaleTotal: amount,
        );
        return result.invoiceNumber;
      } on SqliteException catch (e) {
        if (e.resultCode != 5) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
    fail('processSale remained locked after $maxAttempts attempts');
  }

  Future<String> runCashSale({double amount = 10, double qty = 1}) async {
    final result = await saleService.processSale(
      idempotencyKey: b4IdempotencyKey(),
      fingerprintHash: b4Fingerprint,
      invoice: cashSaleHeader(amount: amount),
      items: cashSaleItems(qty: qty, price: amount / qty),
      debtAmount: 0,
      netSaleTotal: amount,
    );
    return result.invoiceNumber;
  }

  String expectedDayPrefix() =>
      InvoiceNumberService.dayPrefixFor(DateTime.now());

  Future<int?> sequenceForToday() async {
    final prefix = expectedDayPrefix();
    final row = await db.customSelect(
      'SELECT last_number FROM sales_invoice_daily_sequences WHERE day_prefix = ?',
      variables: [Variable.withString(prefix)],
      readsFrom: {db.salesInvoiceDailySequences},
    ).getSingleOrNull();
    return row?.read<int>('last_number');
  }

  Future<List<Map<String, Object?>>> duplicateInvoiceRows() async {
    final rows = await db.customSelect(
      '''
      SELECT invoice_number, COUNT(*) AS cnt
      FROM sales_invoices
      GROUP BY invoice_number
      HAVING COUNT(*) > 1
      ''',
      readsFrom: {db.salesInvoices},
    ).get();
    return rows.map((r) => r.data).toList();
  }

  Future<bool> uniqueIndexExists([AppDatabase? database]) async {
    final target = database ?? db;
    final rows = await target.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name = 'uq_sales_invoices_invoice_number'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> sequencesTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'sales_invoice_daily_sequences'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> seedCommittedSales(int count) async {
    for (var i = 0; i < count; i++) {
      await runCashSale(amount: 10.0 + i);
    }
  }

  group('B4 invoice number atomic allocation', () {
    test('1) first invoice of day is YYYYMMDD-0001', () async {
      final number = await runCashSale();
      expect(number, '${expectedDayPrefix()}-0001');
    });

    test('2) sequential invoice allocation 0001 -> 0002 -> 0003', () async {
      final first = await runCashSale(amount: 10);
      final second = await runCashSale(amount: 11);
      final third = await runCashSale(amount: 12);

      expect(first, '${expectedDayPrefix()}-0001');
      expect(second, '${expectedDayPrefix()}-0002');
      expect(third, '${expectedDayPrefix()}-0003');
    });

    test('3) multiple committed sales have unique invoice numbers', () async {
      final numbers = <String>{
        await runCashSale(amount: 10),
        await runCashSale(amount: 11),
        await runCashSale(amount: 12),
      };
      expect(numbers.length, 3);
      expect(await duplicateInvoiceRows(), isEmpty);
    });

    test('4) dual-connection concurrent processSale yields distinct numbers',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b4_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 10000');
      rawB.execute('PRAGMA busy_timeout = 10000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = PosSaleService(dbA);
      final serviceB = PosSaleService(dbB);

      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Concurrent Product'),
              barcode: Value('B4-CONC-1'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      Future<String> concurrentSale(PosSaleService service) {
        return runCashSaleWithRetry(
          service,
          amount: 10,
          qty: 1,
          saleProductId: pid,
        );
      }

      final numbers = await Future.wait([
        concurrentSale(serviceA),
        concurrentSale(serviceB),
      ]);

      expect(numbers.toSet().length, 2);
      expect(numbers[0], isNot(equals(numbers[1])));

      final rows = await dbA.select(dbA.salesInvoices).get();
      expect(rows.length, 2);
      expect(rows.map((r) => r.invoiceNumber).toSet().length, 2);
      expect(await duplicateInvoiceRows(), isEmpty);
    });

    test('5) duplicate prevention query returns zero rows', () async {
      await runCashSale();
      await runCashSale(amount: 11);
      expect(await duplicateInvoiceRows(), isEmpty);
    });

    test('6) rollback on stock failure does not advance daily counter', () async {
      await seedCommittedSales(7);
      final before = await sequenceForToday();
      expect(before, 7);

      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(currentStock: Value(0)));

      await expectLater(
        saleService.processSale(
          idempotencyKey: b4IdempotencyKey(),
          fingerprintHash: b4Fingerprint,
          invoice: cashSaleHeader(amount: 10),
          items: cashSaleItems(),
          debtAmount: 0,
          netSaleTotal: 10,
        ),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(await db.select(db.salesInvoices).get(), hasLength(7));
      expect(await sequenceForToday(), before);

      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(currentStock: Value(100)));

      final nextNumber = await runCashSale(amount: 99);
      expect(nextNumber, '${expectedDayPrefix()}-0008');
    });

    test('7) rollback on B2 credit block does not advance daily counter',
        () async {
      final customerId = await db.into(db.customers).insert(
            const CustomersCompanion(
              name: Value('B4 Credit Customer'),
              creditLimit: Value(50),
            ),
          );
      await seedCommittedSales(7);
      final before = await sequenceForToday();
      expect(before, 7);

      await expectLater(
        saleService.processSale(
          idempotencyKey: b4IdempotencyKey(),
          fingerprintHash: b4Fingerprint,
          invoice: SalesInvoicesCompanion(
            subtotal: const Value(60),
            total: const Value(60),
            paymentMethod: const Value('DEBT'),
            cashPaid: const Value(0),
            debtAmount: const Value(60),
            customerId: Value(customerId),
          ),
          items: cashSaleItems(qty: 1, price: 60),
          debtAmount: 60,
          netSaleTotal: 60,
        ),
        throwsA(isA<CreditLimitExceededException>()),
      );

      expect(await db.select(db.salesInvoices).get(), hasLength(7));
      expect(await sequenceForToday(), before);

      final nextNumber = await runCashSale(amount: 88);
      expect(nextNumber, '${expectedDayPrefix()}-0008');
    });

    test('8) invoice search/lookup compatibility keeps YYYYMMDD-NNNN format',
        () async {
      final number = await runCashSale();
      expect(RegExp(r'^\d{8}-\d{4}$').hasMatch(number), isTrue);

      final rows = await db.customSelect(
        'SELECT invoice_number FROM sales_invoices WHERE invoice_number LIKE ?',
        variables: [Variable.withString('%${number.substring(number.length - 4)}%')],
        readsFrom: {db.salesInvoices},
      ).get();
      expect(rows.length, 1);
      expect(rows.single.read<String>('invoice_number'), number);
    });

    test('9) receipt/display compatibility returns allocated number from processSale',
        () async {
      final result = await saleService.processSale(
        idempotencyKey: b4IdempotencyKey(),
        fingerprintHash: b4Fingerprint,
        invoice: cashSaleHeader(amount: 15),
        items: cashSaleItems(qty: 1, price: 15),
        debtAmount: 0,
        netSaleTotal: 15,
      );
      expect(result.invoiceNumber, isNotEmpty);
      expect(result.invoiceId, greaterThan(0));

      final stored = await (db.select(db.salesInvoices)
            ..where((i) => i.id.equals(result.invoiceId)))
          .getSingle();
      expect(stored.invoiceNumber, result.invoiceNumber);
    });

    test('10) v35 to v36 migration backfills counter from existing invoices',
        () async {
      const prefix = '20260115';
      const otherPrefix = '20260116';
      final fixture = await openSimulatedV35RawDatabase();
      final rawDb = fixture.rawDb;
      addTearDown(() {
        rawDb.dispose();
        File(fixture.path).deleteSync();
      });

      expect(rawDb.userVersion, 35);
      insertLegacySalesInvoice(rawDb, '$prefix-0001');
      insertLegacySalesInvoice(rawDb, '$prefix-0007');
      insertLegacySalesInvoice(rawDb, '$otherPrefix-0003');
      final beforeMigration = await legacyInvoiceNumbers(rawDb);

      final migrated = AppDatabase.test(NativeDatabase.opened(rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 45);
      expect(await sequencesTableExists(migrated), isTrue);
      expect(await uniqueIndexExists(migrated), isTrue);

      final afterMigration = await (migrated.select(migrated.salesInvoices)
            ..orderBy([
              (i) => OrderingTerm.asc(i.invoiceNumber),
              (i) => OrderingTerm.asc(i.id),
            ]))
          .get();
      expect(
        afterMigration.map((r) => r.invoiceNumber).toList(),
        beforeMigration,
      );

      final backfillRow = await migrated.customSelect(
        'SELECT last_number FROM sales_invoice_daily_sequences WHERE day_prefix = ?',
        variables: [Variable.withString(prefix)],
        readsFrom: {migrated.salesInvoiceDailySequences},
      ).getSingle();
      expect(backfillRow.read<int>('last_number'), 7);

      final otherDayRow = await migrated.customSelect(
        'SELECT last_number FROM sales_invoice_daily_sequences WHERE day_prefix = ?',
        variables: [Variable.withString(otherPrefix)],
        readsFrom: {migrated.salesInvoiceDailySequences},
      ).getSingle();
      expect(otherDayRow.read<int>('last_number'), 3);

      final allocated = await migrated.transaction(() async {
        return InvoiceNumberService(migrated).allocateNextInTransaction(
          date: DateTime(2026, 1, 15),
        );
      });
      expect(allocated, '$prefix-0008');

      final otherDayAllocated = await migrated.transaction(() async {
        return InvoiceNumberService(migrated).allocateNextInTransaction(
          date: DateTime(2026, 1, 16),
        );
      });
      expect(otherDayAllocated, '$otherPrefix-0004');
    });

    test('13) v35 to v36 migration fails on duplicate invoice_number audit',
        () async {
      const duplicateNumber = '20260115-0007';
      final fixture = await openSimulatedV35RawDatabase();
      final rawDb = fixture.rawDb;
      addTearDown(() => File(fixture.path).deleteSync());

      insertLegacySalesInvoice(rawDb, duplicateNumber);
      insertLegacySalesInvoice(rawDb, duplicateNumber);
      final beforeMigration = await legacyInvoiceNumbers(rawDb);
      expect(beforeMigration, [duplicateNumber, duplicateNumber]);

      await expectLater(
        () async {
          final migrated = AppDatabase.test(NativeDatabase.opened(rawDb));
          try {
            await migrated.select(migrated.salesInvoices).get();
          } finally {
            await migrated.close();
          }
        }(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('B4 migration blocked'),
          ),
        ),
      );

      // Reopen the file: Drift closes the shared raw handle during migration.
      rawDb.dispose();
      final verifyDb = sqlite3.sqlite3.open(fixture.path);
      addTearDown(verifyDb.dispose);

      expect(verifyDb.userVersion, 35);
      expect(await legacyInvoiceNumbers(verifyDb), beforeMigration);

      final sequences = verifyDb.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'sales_invoice_daily_sequences'",
      );
      expect(sequences, isEmpty);

      final uniqueIndex = verifyDb.select(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'uq_sales_invoices_invoice_number'",
      );
      expect(uniqueIndex, isEmpty);
    });

    test('11) UNIQUE constraint rejects direct duplicate insert', () async {
      final prefix = expectedDayPrefix();
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion(
              invoiceNumber: Value('$prefix-9999'),
              subtotal: const Value(10),
              total: const Value(10),
              paymentMethod: const Value('CASH'),
              cashPaid: const Value(10),
            ),
          );

      await expectLater(
        db.into(db.salesInvoices).insert(
              SalesInvoicesCompanion(
                invoiceNumber: Value('$prefix-9999'),
                subtotal: const Value(10),
                total: const Value(10),
                paymentMethod: const Value('CASH'),
                cashPaid: const Value(10),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('12) legacy format parsing ignores non-conforming invoice numbers',
        () async {
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion(
              invoiceNumber: const Value('B4-LEGACY-TEST'),
              subtotal: const Value(10),
              total: const Value(10),
              paymentMethod: const Value('CASH'),
              cashPaid: const Value(10),
            ),
          );

      expect(
        InvoiceNumberService.parseConformingSuffix('B4-LEGACY-TEST'),
        isNull,
      );
      expect(
        InvoiceNumberService.parseConformingSuffix('20260115-0003'),
        3,
      );

      final number = await runCashSale();
      expect(number, '${expectedDayPrefix()}-0001');
    });

    test('schema v41 includes B4 sequences and idempotency tables', () async {
      expect(db.schemaVersion, 45);
      expect(await uniqueIndexExists(), isTrue);

      final tables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'sales_invoice_daily_sequences'",
      ).get();
      expect(tables.length, 1);

      final idempotencyTables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'pos_sale_idempotency'",
      ).get();
      expect(idempotencyTables.length, 1);

      final paymentIdempotencyTables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'customer_payment_idempotency'",
      ).get();
      expect(paymentIdempotencyTables.length, 1);
    });

  });
}