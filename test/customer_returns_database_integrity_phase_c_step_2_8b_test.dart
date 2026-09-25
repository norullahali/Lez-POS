import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/returns/repositories/customer_return_read_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late AppDatabase db;
  late PartialReturnService partialService;
  late CustomerReturnReadRepository readRepo;
  late int customerId;
  late int cashCustomerId;
  late int productAId;
  late int productBId;
  late int productCId;
  late int invoiceId;
  late int saleItemAId;
  late int saleItemBId;
  const returnedByUserId = 1;

  Future<void> seedProducts() async {
    productAId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product A'),
            barcode: Value('CR6-A'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    productBId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product B'),
            barcode: Value('CR6-B'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    productCId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Product C'),
            barcode: Value('CR6-C'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  }

  Future<int> createCreditInvoice({
    double debtAmount = 400,
    int? customer,
  }) async {
    final cid = customer ?? customerId;
    invoiceId = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('SI6-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: const Value(400),
        total: const Value(400),
        debtAmount: Value(debtAmount),
        customerId: Value(cid),
        paymentMethod: const Value('DEBT'),
      ),
      items: [
        {'productId': productAId, 'qty': 10.0, 'price': 10.0, 'cost': 5.0},
        {'productId': productBId, 'qty': 5.0, 'price': 20.0, 'cost': 5.0},
        {'productId': productCId, 'qty': 8.0, 'price': 25.0, 'cost': 5.0},
      ],
    );

    final items = await db.salesDao.getItemsForInvoice(invoiceId);
    saleItemAId = items.firstWhere((i) => i.productId == productAId).id;
    saleItemBId = items.firstWhere((i) => i.productId == productBId).id;

    if (debtAmount > 0) {
      await db.customerAccountsDao.recordSale(
        customerId: cid,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'test credit sale',
      );
    }
    return invoiceId;
  }

  setUp(() async {
    db = AppDatabase.test();
    partialService = PartialReturnService(db);
    readRepo = CustomerReturnReadRepository(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Credit Customer')),
        );
    cashCustomerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Cash Customer')),
        );
    await seedProducts();
    await createCreditInvoice();
  });

  tearDown(() async => db.close());

  PartialReturnLine line({
    required int saleItemId,
    required int productId,
    required double qty,
    required double price,
  }) =>
      PartialReturnLine(
        saleItemId: saleItemId,
        productId: productId,
        quantity: qty,
        unitPrice: price,
        unitCost: 5,
      );

  Future<int> headerCount() async =>
      (await db.select(db.customerReturns).get()).length;

  Future<int> itemCount() async =>
      (await db.select(db.customerReturnItems).get()).length;

  Future<int> saleItemReturnCount() async =>
      (await db.select(db.saleItemReturns).get()).length;

  Future<int> returnTxnCount() async =>
      (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('RETURN')))
              .get())
          .length;

  Future<double> creditReversedForInvoice() =>
      db.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
        customerId: customerId,
        invoiceId: invoiceId,
      );

  Future<double> productStock(int productId) => db.stockDao.getStock(productId);

  Future<CustomerReturn?> headerForInvoice() =>
      db.returnsDao.findCustomerReturnByOriginalInvoiceId(invoiceId);
  Future<bool> uniqueIndexExists(AppDatabase database) async {
    final rows = await database.customSelect(
      '''
      SELECT name FROM sqlite_master
      WHERE type = 'index' AND name = 'uq_customer_returns_original_invoice'
      ''',
    ).get();
    return rows.isNotEmpty;
  }

  Future<int> refundTxnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.customerTransactions)
              ..where((t) => t.type.equals('REFUND')))
            .get())
        .length;
  }

  Future<AppDatabase> openDatabaseAtV32({
    required List<Map<String, dynamic>> returns,
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
        notes TEXT NOT NULL DEFAULT '',
        settled_amount REAL NOT NULL DEFAULT 0
      );
    ''');

    rawDb.execute(
      "INSERT INTO customers (id, name) VALUES (1, 'Migration Customer');",
    );

    for (final row in returns) {
      rawDb.execute(
        '''
        INSERT INTO customer_returns
          (id, original_invoice_id, return_number, return_date, total, reason, notes, settled_amount)
        VALUES (?, ?, ?, ?, ?, '', '', ?);
        ''',
        [
          row['id'],
          row['originalInvoiceId'],
          row['returnNumber'],
          DateTime.now().millisecondsSinceEpoch,
          row['total'],
          row['settledAmount'] ?? 0,
        ],
      );
    }

    rawDb.userVersion = 32;

    return AppDatabase.test(NativeDatabase.opened(rawDb));
  }

  group('Phase C Step 2.8B customer_returns database integrity', () {
    test('A) schema version is 34', () {
      expect(db.schemaVersion, 34);
    });

    test('B) partial unique index exists', () async {
      expect(await uniqueIndexExists(db), isTrue);
    });
    test(
        'C) first invoice-linked header inserts on partial return creates exactly one customer_returns header',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await headerCount(), 1);
      final header = await headerForInvoice();
      expect(header, isNotNull);
      expect(header!.originalInvoiceId, invoiceId);
    });

    test('B-skip) first partial return creates correct customer_return_items',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await itemCount(), 1);
      final header = await headerForInvoice();
      final items = await db.returnsDao.getCustomerReturnItems(header!.id);
      expect(items.single.productId, productAId);
      expect(items.single.productName, 'Product A');
      expect(items.single.quantity, closeTo(2, 0.001));
      expect(items.single.unitPrice, closeTo(10, 0.001));
      expect(items.single.total, closeTo(20, 0.001));
    });

    test('D) second partial batch reuses the same header', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      final firstHeader = await headerForInvoice();

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      expect(await headerCount(), 1);
      final secondHeader = await headerForInvoice();
      expect(secondHeader!.id, firstHeader!.id);
    });

    test('D-items) second batch appends customer_return_items', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      expect(await itemCount(), 2);
    });

    test('F) multiple NULL original_invoice_id rows are allowed', () async {
      await db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              returnNumber:
                  Value('MAN-1-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(10),
            ),
          );
      await db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              returnNumber:
                  Value('MAN-2-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(20),
            ),
          );

      final nullHeaders = (await db.select(db.customerReturns).get())
          .where((h) => h.originalInvoiceId == null)
          .length;
      expect(nullHeaders, greaterThanOrEqualTo(2));
    });

    test(
        'G) duplicate invoice-linked insert is ignored by partial unique index',
        () async {
      final firstId = await db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              originalInvoiceId: Value(invoiceId),
              returnNumber:
                  Value('PRE-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(50),
            ),
          );

      final ignoredId = await db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              originalInvoiceId: Value(invoiceId),
              returnNumber:
                  Value('DUP-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(99),
            ),
            mode: InsertMode.insertOrIgnore,
          );

      final headers = await db.select(db.customerReturns).get();
      final linked =
          headers.where((h) => h.originalInvoiceId == invoiceId).toList();
      expect(linked.length, 1);
      expect(linked.single.id, firstId);
      expect(linked.single.total, 50);
      expect(ignoredId == 0 || ignoredId == firstId, isTrue);
    });

    test('I) INSERT OR IGNORE conflict path reuses header and increments total',
        () async {
      final preId = await db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              originalInvoiceId: Value(invoiceId),
              returnNumber:
                  Value('PRE-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(25),
            ),
          );

      final upsertId = await db.transaction(
        () => db.returnsDao.upsertPartialReturnDocumentHeader(
          saleInvoiceId: invoiceId,
          invoiceNumber: 'SI-TEST',
          batchGoodsTotal: 15,
          returnReason: 'conflict test',
        ),
      );

      expect(upsertId, preId);
      final header = await db.returnsDao.getCustomerReturnById(preId);
      expect(header!.total, closeTo(40, 0.001));
    });

    test('P) refund architecture regression - partial return creates no REFUND',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await refundTxnCount(), 0);
      expect(await returnTxnCount(), 1);
    });

    test('Q) migration from schema 32 to 33 succeeds on clean fixture',
        () async {
      final migrated = await openDatabaseAtV32(
        returns: [
          {
            'id': 1,
            'originalInvoiceId': 100,
            'returnNumber': 'RET-100',
            'total': 50,
          },
          {
            'id': 2,
            'originalInvoiceId': null,
            'returnNumber': 'RET-MANUAL',
            'total': 30,
            'settledAmount': 5,
          },
        ],
      );
      addTearDown(migrated.close);

      expect(migrated.schemaVersion, 34);
      expect(await uniqueIndexExists(migrated), isTrue);

      final linked = await migrated.returnsDao.getCustomerReturnById(1);
      final manual = await migrated.returnsDao.getCustomerReturnById(2);
      expect(linked!.originalInvoiceId, 100);
      expect(manual!.originalInvoiceId, isNull);
      expect(manual.settledAmount, 5);
    });

    test('R) migration does not reject legitimate NULL headers', () async {
      final migrated = await openDatabaseAtV32(
        returns: [
          {
            'id': 10,
            'originalInvoiceId': null,
            'returnNumber': 'RET-A',
            'total': 10,
          },
          {
            'id': 11,
            'originalInvoiceId': null,
            'returnNumber': 'RET-B',
            'total': 20,
          },
        ],
      );
      addTearDown(migrated.close);

      final headers = await migrated.select(migrated.customerReturns).get();
      expect(headers.where((h) => h.originalInvoiceId == null).length, 2);
    });

    test('S) duplicate fixture migration gate rejects before index creation',
        () async {
      final rawDb = sqlite3.sqlite3.openInMemory();
      rawDb.execute('''
        CREATE TABLE customer_returns (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          original_invoice_id INTEGER,
          return_number TEXT NOT NULL,
          return_date INTEGER NOT NULL DEFAULT 0,
          total REAL NOT NULL DEFAULT 0,
          reason TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          settled_amount REAL NOT NULL DEFAULT 0
        );
      ''');
      rawDb.execute(
        "INSERT INTO customer_returns (id, original_invoice_id, return_number, total) VALUES (1, 200, 'RET-A', 10);",
      );
      rawDb.execute(
        "INSERT INTO customer_returns (id, original_invoice_id, return_number, total) VALUES (2, 200, 'RET-B', 20);",
      );
      rawDb.userVersion = 32;

      await expectLater(
        () async {
          final migrated = AppDatabase.test(NativeDatabase.opened(rawDb));
          addTearDown(migrated.close);
          await migrated.customSelect('SELECT 1').get();
        }(),
        throwsA(isA<StateError>()),
      );
    });
    test('E) header total accumulates across batches', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      final header = await headerForInvoice();
      expect(header!.total, closeTo(40, 0.001));
    });

    test('F-dup) no duplicate customer_returns header exists for the invoice',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );

      final headers = await db.select(db.customerReturns).get();
      expect(headers.where((h) => h.originalInvoiceId == invoiceId).length, 1);
    });

    test('H) concurrent header upserts share one customer_returns row',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}c28b_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawSetup = sqlite3.sqlite3.open(dbPath);
      addTearDown(() {
        File(dbPath).deleteSync();
      });

      final db = AppDatabase.test(NativeDatabase.opened(rawSetup));

      final productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Concurrent Product'),
              barcode: Value('C28B-P'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );

      final invId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('C28B-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(100),
          total: const Value(100),
          debtAmount: const Value(0),
          paymentMethod: const Value('CASH'),
        ),
        items: [
          {'productId': productId, 'qty': 1.0, 'price': 100.0, 'cost': 5.0},
        ],
      );

      await db.close();
      rawSetup.dispose();

      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 10000');
      rawB.execute('PRAGMA busy_timeout = 10000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
      });

      Future<int> rawUpsert(
        sqlite3.Database conn,
        double batchTotal,
        String suffix,
      ) async {
        conn.execute('BEGIN IMMEDIATE');
        try {
          conn.execute(
            '''
            INSERT OR IGNORE INTO customer_returns
              (original_invoice_id, return_number, total, reason, notes, settled_amount)
            VALUES (?, ?, ?, '', '', 0)
            ''',
            [
              invId,
              'RAW-$suffix-${DateTime.now().microsecondsSinceEpoch}',
              batchTotal
            ],
          );
          final insertedId = conn.lastInsertRowId;
          if (insertedId != 0) {
            conn.execute('COMMIT');
            return insertedId;
          }
          final row = conn.select(
            'SELECT id, total FROM customer_returns WHERE original_invoice_id = ?',
            [invId],
          ).first;
          conn.execute(
            'UPDATE customer_returns SET total = ? WHERE id = ?',
            [(row.columnAt(1) as num).toDouble() + batchTotal, row.columnAt(0)],
          );
          conn.execute('COMMIT');
          return row.columnAt(0) as int;
        } catch (e) {
          conn.execute('ROLLBACK');
          rethrow;
        }
      }

      final ids = await Future.wait([
        rawUpsert(rawA, 20, 'A'),
        rawUpsert(rawB, 30, 'B'),
      ]);

      expect(ids.toSet().length, 1);

      final verifyDb = AppDatabase.test(NativeDatabase.opened(rawA));
      addTearDown(verifyDb.close);
      final headers = await verifyDb.select(verifyDb.customerReturns).get();
      expect(
        headers.where((h) => h.originalInvoiceId == invId).length,
        1,
      );
      expect(
        headers.singleWhere((h) => h.originalInvoiceId == invId).total,
        closeTo(50, 0.001),
      );
    });
    test('J) returnAllRemaining reuses the same header', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      final before = (await headerForInvoice())!.id;

      await partialService.returnAllRemainingSaleInvoice(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'finish remaining',
      );

      expect(await headerCount(), 1);
      expect((await headerForInvoice())!.id, before);
    });

    test('K) partial then full uses the same header', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      final before = (await headerForInvoice())!.id;

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'finish via full return',
        returnedByUserId: returnedByUserId,
      );

      expect(await headerCount(), 1);
      expect((await headerForInvoice())!.id, before);
    });

    test('L) clean full return creates one header', () async {
      await db.close();
      db = AppDatabase.test();
      partialService = PartialReturnService(db);
      await seedProducts();
      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Clean Full Customer')),
          );
      await createCreditInvoice();

      final returnId = await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'clean full',
        returnedByUserId: returnedByUserId,
      );

      expect(returnId, greaterThan(0));
      expect(await headerCount(), 1);
      final header = await headerForInvoice();
      expect(header!.total, closeTo(400, 0.001));
    });

    test('J) existing sale_item_returns behavior remains unchanged', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await saleItemReturnCount(), 1);
      final sir = await db.select(db.saleItemReturns).getSingle();
      expect(sir.saleInvoiceId, invoiceId);
      expect(sir.saleItemId, saleItemAId);
      expect(sir.returnedQuantity, closeTo(2, 0.001));
    });

    test('K) existing stock behavior remains unchanged', () async {
      final stockBefore = await productStock(productAId);

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await productStock(productAId), closeTo(stockBefore + 2, 0.001));
    });

    test('L) existing customer RETURN transaction remains unchanged', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      expect(await returnTxnCount(), 1);
      expect(await creditReversedForInvoice(), closeTo(40, 0.01));
    });

    test('M) RETURN reference_id remains sale_item_returns.id', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );

      final sirRow = await db.select(db.saleItemReturns).getSingle();
      final returnTxn = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('RETURN')))
              .get())
          .single;
      expect(returnTxn.referenceId, sirRow.id);
      expect(sirRow.saleInvoiceId, invoiceId);
    });

    test('N) getCreditReversalTotalForSaleInvoice behavior remains unchanged',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 4, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 2, price: 20)
        ],
      );

      expect(await creditReversedForInvoice(), closeTo(80, 0.01));
    });

    test('M) cash invoice partial return behavior unchanged', () async {
      final cashInvoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber:
              Value('CASH6-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(100),
          total: const Value(100),
          debtAmount: const Value(0),
          cashPaid: const Value(100),
          customerId: Value(cashCustomerId),
          paymentMethod: const Value('CASH'),
        ),
        items: [
          {'productId': productAId, 'qty': 10.0, 'price': 10.0, 'cost': 5.0},
        ],
      );
      final cashItemId =
          (await db.salesDao.getItemsForInvoice(cashInvoiceId)).single.id;

      await partialService.processPartialReturn(
        saleInvoiceId: cashInvoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(saleItemId: cashItemId, productId: productAId, qty: 2, price: 10)
        ],
      );

      expect(await returnTxnCount(), 0);
      final header = await db.returnsDao
          .findCustomerReturnByOriginalInvoiceId(cashInvoiceId);
      expect(header, isNotNull);
      expect(
          await db.returnsDao.getCustomerReturnItems(header!.id), isNotEmpty);
    });

    test('N) Customer Returns read path behavior unchanged', () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );

      final header = await headerForInvoice();
      final detail = await readRepo.getCustomerReturnDetail(header!.id);
      expect(detail, isNotNull);
      expect(detail!.originalInvoiceId, invoiceId);
      expect(detail.customerId, customerId);
      expect(detail.isRefundLinkEligible, isTrue);
      expect(detail.lines, isNotEmpty);
    });

    test(
        'Q) rollback removes customer_returns and sale_item_returns on failure',
        () async {
      final stockBefore = await productStock(productAId);
      final failingService = PartialReturnService.withCreditPoster(
        db,
        creditPoster: ({
          required int customerId,
          required double amount,
          required int returnId,
          String note = '',
        }) async {
          throw Exception('forced accounting failure');
        },
      );

      await expectLater(
        failingService.processPartialReturn(
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [
            line(
                saleItemId: saleItemAId,
                productId: productAId,
                qty: 4,
                price: 10)
          ],
        ),
        throwsA(isA<Exception>()),
      );

      expect(await headerCount(), 0);
      expect(await itemCount(), 0);
      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await productStock(productAId), closeTo(stockBefore, 0.001));
    });

    test(
        'R-batches) multiple batches remain one header when invoice fully returned',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemBId, productId: productBId, qty: 1, price: 20)
        ],
      );
      await partialService.returnAllRemainingSaleInvoice(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'complete',
      );

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
      expect(await headerCount(), 1);
    });

    test('S-full) no duplicate header when invoice becomes fully returned',
        () async {
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          line(
              saleItemId: saleItemAId, productId: productAId, qty: 2, price: 10)
        ],
      );
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'complete via full return',
        returnedByUserId: returnedByUserId,
      );

      expect(await headerCount(), 1);
      final headers = await db.select(db.customerReturns).get();
      expect(headers.where((h) => h.originalInvoiceId == invoiceId).length, 1);
    });
  });
}
