import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late AppDatabase db;
  late PartialReturnService service;
  late int customerId;
  late int productId;
  late int saleItemId;
  late int invoiceId;
  const returnedByUserId = 1;
  const unitPrice = 10.0;

  Future<void> seedCreditSale({
    required AppDatabase target,
    double saleQty = 10,
    double initialStock = 100,
  }) async {
    customerId = await target.into(target.customers).insert(
          const CustomersCompanion(name: Value('CR 2.3 Customer')),
        );
    productId = await target.into(target.products).insert(
          ProductsCompanion(
            name: const Value('Concurrency Product'),
            currentStock: Value(initialStock),
            costPrice: const Value(5),
          ),
        );
    final goodsTotal = saleQty * unitPrice;
    invoiceId = await target.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('SI-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(goodsTotal),
        total: Value(goodsTotal),
        debtAmount: Value(goodsTotal),
        cashPaid: const Value(0),
        customerId: Value(customerId),
        paymentMethod: const Value('DEBT'),
      ),
      items: [
        {'productId': productId, 'qty': saleQty, 'price': unitPrice, 'cost': 5.0},
      ],
    );
    final items = await target.salesDao.getItemsForInvoice(invoiceId);
    saleItemId = items.single.id;
    await target.customerAccountsDao.recordSale(
      customerId: customerId,
      amount: goodsTotal,
      invoiceId: invoiceId,
      note: 'test credit sale',
    );
  }

  PartialReturnLine returnLine({required double quantity}) => PartialReturnLine(
        saleItemId: saleItemId,
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
        unitCost: 5,
      );

  Future<void> processReturn(
    PartialReturnService targetService, {
    required double quantity,
  }) =>
      targetService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: quantity)],
        note: 'concurrency test',
      );

  Future<double> returnedQuantity([AppDatabase? target]) async {
    final database = target ?? db;
    final row = await database.customSelect(
      '''
      SELECT COALESCE(SUM(returned_quantity), 0) AS total
      FROM sale_item_returns
      WHERE sale_item_id = ?
      ''',
      variables: [Variable.withInt(saleItemId)],
      readsFrom: {database.saleItemReturns},
    ).getSingle();
    return (row.data['total'] as num).toDouble();
  }

  Future<int> saleItemReturnRowCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.saleItemReturns).get()).length;
  }

  Future<int> customerReturnHeaderCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.customerReturns).get()).length;
  }

  Future<int> customerReturnItemCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.customerReturnItems).get()).length;
  }

  Future<int> returnTxnCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.customerTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get())
        .length;
  }

  Future<int> returnInLedgerCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.stockLedger)
          ..where((l) => l.movementType.equals(StockMovementType.returnIn.code)))
        .get())
        .length;
  }

  Future<double> productStock([AppDatabase? target]) async {
    final database = target ?? db;
    return database.stockDao.getStock(productId);
  }

  Future<double> customerBalance([AppDatabase? target]) async {
    final database = target ?? db;
    return database.customerAccountsDao.getBalance(customerId);
  }

  Future<String?> invoiceStatus([AppDatabase? target]) async {
    final database = target ?? db;
    final inv = await database.salesDao.getInvoiceById(invoiceId);
    return inv?.invoiceStatus;
  }

  Future<Object?> runConcurrentPartialReturn(
    PartialReturnService targetService, {
    required double quantity,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await processReturn(targetService, quantity: quantity);
        return true;
      } on StateError catch (e) {
        return e;
      } catch (e) {
        final message = e.toString();
        final isBusy = message.contains('database is locked') ||
            message.contains('SqliteException(5)');
        if (isBusy && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
    throw StateError('concurrent partial return exhausted busy retries');
  }

  setUp(() async {
    db = AppDatabase.test();
    service = PartialReturnService(db);
    await seedCreditSale(target: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase C Step 2.3 customer partial return quantity concurrency', () {
    test('CASE 1) concurrent 6 + 4 both succeed with total returned 10',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}cr23_1_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 5000');
      rawB.execute('PRAGMA busy_timeout = 5000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      await seedCreditSale(target: dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = PartialReturnService(dbA);
      final serviceB = PartialReturnService(dbB);
      final stockBefore = await productStock(dbA);
      final balanceBefore = await customerBalance(dbA);

      final outcomes = await Future.wait<Object?>([
        runConcurrentPartialReturn(serviceA, quantity: 6),
        runConcurrentPartialReturn(serviceB, quantity: 4),
      ]);

      expect(outcomes.whereType<bool>().length, 2);
      expect(await returnedQuantity(dbA), 10);
      expect(await saleItemReturnRowCount(dbA), 2);
      expect(await customerReturnHeaderCount(dbA), 1);
      expect(await customerReturnItemCount(dbA), 2);
      expect(await returnTxnCount(dbA), 2);
      expect(await returnInLedgerCount(dbA), 2);
      expect(await productStock(dbA), closeTo(stockBefore + 10, 0.001));
      expect(await customerBalance(dbA), closeTo(balanceBefore - 100, 0.01));
      expect(
        await invoiceStatus(dbA),
        InvoiceLifecycleStatus.returned,
      );
    });

    test('CASE 2) concurrent 6 + 5 allows only one success', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}cr23_2_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 5000');
      rawB.execute('PRAGMA busy_timeout = 5000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      await seedCreditSale(target: dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = PartialReturnService(dbA);
      final serviceB = PartialReturnService(dbB);

      final outcomes = await Future.wait<Object?>([
        runConcurrentPartialReturn(serviceA, quantity: 6),
        runConcurrentPartialReturn(serviceB, quantity: 5),
      ]);

      expect(outcomes.whereType<bool>().length, 1);
      expect(outcomes.whereType<StateError>().length, 1);

      final totalReturned = await returnedQuantity(dbA);
      expect(totalReturned, lessThanOrEqualTo(10));
      expect(totalReturned, greaterThan(0));
      expect(await saleItemReturnRowCount(dbA), 1);
      expect(await customerReturnHeaderCount(dbA), 1);
      expect(await customerReturnItemCount(dbA), 1);
      expect(await returnTxnCount(dbA), 1);
      expect(await returnInLedgerCount(dbA), 1);
    });

    test('CASE 3) concurrent 10 + 1 allows only total returned 10', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}cr23_3_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 5000');
      rawB.execute('PRAGMA busy_timeout = 5000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      await seedCreditSale(target: dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = PartialReturnService(dbA);
      final serviceB = PartialReturnService(dbB);
      final stockBefore = await productStock(dbA);
      final balanceBefore = await customerBalance(dbA);

      final outcomes = await Future.wait<Object?>([
        runConcurrentPartialReturn(serviceA, quantity: 10),
        runConcurrentPartialReturn(serviceB, quantity: 1),
      ]);

      expect(outcomes.whereType<bool>().length, 1);
      expect(outcomes.whereType<StateError>().length, 1);

      final totalReturned = await returnedQuantity(dbA);
      expect(totalReturned, lessThanOrEqualTo(10));
      expect(totalReturned, greaterThan(0));
      expect(totalReturned == 10 || totalReturned == 1, isTrue);

      expect(await saleItemReturnRowCount(dbA), 1);
      expect(await customerReturnHeaderCount(dbA), 1);
      expect(await returnTxnCount(dbA), 1);
      expect(await productStock(dbA), closeTo(stockBefore + totalReturned, 0.001));
      expect(
        await customerBalance(dbA),
        closeTo(balanceBefore - (totalReturned * unitPrice), 0.01),
      );
    });

    test('CASE 4) concurrent partial-return documents 7 + 3 total 10', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}cr23_4_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 5000');
      rawB.execute('PRAGMA busy_timeout = 5000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      await seedCreditSale(target: dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = PartialReturnService(dbA);
      final serviceB = PartialReturnService(dbB);

      final outcomes = await Future.wait<Object?>([
        runConcurrentPartialReturn(serviceA, quantity: 7),
        runConcurrentPartialReturn(serviceB, quantity: 3),
      ]);

      expect(outcomes.whereType<bool>().length, 2);
      expect(await returnedQuantity(dbA), 10);
      expect(await saleItemReturnRowCount(dbA), 2);
      expect(await customerReturnHeaderCount(dbA), 1);
      expect(await customerReturnItemCount(dbA), 2);
      expect(await returnTxnCount(dbA), 2);
    });

    test('CASE 5) sequential 6 + 4 succeeds with total 10', () async {
      await processReturn(service, quantity: 6);
      await processReturn(service, quantity: 4);

      expect(await returnedQuantity(), 10);
      expect(await saleItemReturnRowCount(), 2);
      expect(await customerReturnHeaderCount(), 1);
      expect(await returnTxnCount(), 2);
    });

    test('CASE 6) sequential 6 + 5 rejects second with total 6', () async {
      final stockBefore = await productStock();
      final balanceBefore = await customerBalance();

      await processReturn(service, quantity: 6);

      await expectLater(
        processReturn(service, quantity: 5),
        throwsA(isA<StateError>()),
      );

      expect(await returnedQuantity(), 6);
      expect(await saleItemReturnRowCount(), 1);
      expect(await customerReturnHeaderCount(), 1);
      expect(await customerReturnItemCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await returnInLedgerCount(), 1);
      expect(await productStock(), closeTo(stockBefore + 6, 0.001));
      expect(await customerBalance(), closeTo(balanceBefore - 60, 0.01));
    });

    test('CASE 7) losing concurrent transaction leaves no orphan mutations',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}cr23_7_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 5000');
      rawB.execute('PRAGMA busy_timeout = 5000');
      addTearDown(() {
        rawA.dispose();
        rawB.dispose();
        File(dbPath).deleteSync();
      });

      final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
      await seedCreditSale(target: dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = PartialReturnService(dbA);
      final serviceB = PartialReturnService(dbB);
      final stockBefore = await productStock(dbA);
      final balanceBefore = await customerBalance(dbA);

      final outcomes = await Future.wait<Object?>([
        runConcurrentPartialReturn(serviceA, quantity: 7),
        runConcurrentPartialReturn(serviceB, quantity: 7),
      ]);

      expect(outcomes.whereType<bool>().length, 1);
      expect(outcomes.whereType<StateError>().length, 1);

      expect(await returnedQuantity(dbA), 7);
      expect(await saleItemReturnRowCount(dbA), 1);
      expect(await customerReturnHeaderCount(dbA), 1);
      expect(await customerReturnItemCount(dbA), 1);
      expect(await returnTxnCount(dbA), 1);
      expect(await returnInLedgerCount(dbA), 1);
      expect(await productStock(dbA), closeTo(stockBefore + 7, 0.001));
      expect(await customerBalance(dbA), closeTo(balanceBefore - 70, 0.01));
      expect(
        await invoiceStatus(dbA),
        InvoiceLifecycleStatus.partiallyReturned,
      );
    });
  });
}
