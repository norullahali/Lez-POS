import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late AppDatabase db;
  late SupplierReturnService service;
  late int supplierId;
  late int productId;
  late int purchaseItemId;
  late int invoiceId;

  Future<void> seedPurchase({
    required AppDatabase target,
    double purchaseQty = 10,
    double initialStock = 0,
  }) async {
    supplierId = await target.into(target.suppliers).insert(
          const SuppliersCompanion(name: Value('SR 2.3 Supplier')),
        );
    productId = await target.into(target.products).insert(
          ProductsCompanion(
            name: const Value('Concurrency Part'),
            currentStock: Value(initialStock),
          ),
        );
    invoiceId = await target.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(supplierId),
        purchaseDate: Value(DateTime(2026, 3, 1)),
        total: Value(purchaseQty * 5),
        paidAmount: const Value(0),
        debtAmount: Value(purchaseQty * 5),
      ),
      items: [
        {'productId': productId, 'qty': purchaseQty, 'cost': 5.0},
      ],
    );
    final items = await target.purchasesDao.getItemsForInvoice(invoiceId);
    purchaseItemId = items.single.id;
  }

  SupplierReturnPostingInput postingInput({required double quantity}) {
    return SupplierReturnPostingInput(
      supplierId: supplierId,
      purchaseInvoiceId: invoiceId,
      lines: [
        SupplierReturnPostingLine(
          purchaseItemId: purchaseItemId,
          quantity: quantity,
        ),
      ],
    );
  }

  Future<double> returnedQuantity([AppDatabase? target]) async {
    final database = target ?? db;
    final row = await database.customSelect(
      '''
      SELECT COALESCE(SUM(quantity), 0) AS total
      FROM supplier_return_items
      WHERE purchase_item_id = ?
      ''',
      variables: [Variable.withInt(purchaseItemId)],
      readsFrom: {database.supplierReturnItems},
    ).getSingle();
    return (row.data['total'] as num).toDouble();
  }

  Future<int> returnHeaderCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.supplierReturns).get()).length;
  }

  Future<int> returnItemCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await database.select(database.supplierReturnItems).get()).length;
  }

  Future<int> returnOutCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.stockLedger)
          ..where((l) =>
              l.movementType.equals(StockMovementType.returnOut.code)))
        .get())
        .length;
  }

  Future<int> supplierReturnTxnCount([AppDatabase? target]) async {
    final database = target ?? db;
    return (await (database.select(database.supplierTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get())
        .length;
  }

  Future<double> productStock([AppDatabase? target]) async {
    final database = target ?? db;
    return database.stockDao.getStock(productId);
  }

  Future<Object?> runConcurrentReturn(
    SupplierReturnService targetService,
    SupplierReturnPostingInput input,
  ) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await targetService.postPurchaseLinkedReturn(input);
      } on SupplierReturnPostingException catch (e) {
        return e.code;
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
    throw StateError('concurrent return exhausted busy retries');
  }

  setUp(() async {
    db = AppDatabase.test();
    service = SupplierReturnService(db);
    await seedPurchase(target: db, initialStock: 4);
  });

  tearDown(() async {
    await db.close();
  });

  group('SR Step 2.3 supplier return quantity concurrency', () {
    test('A) two concurrent returns - only one succeeds for 7 + 7 on qty 10',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}sr23a_${DateTime.now().microsecondsSinceEpoch}.db';
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
      await seedPurchase(target: dbA, initialStock: 4);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = SupplierReturnService(dbA);
      final serviceB = SupplierReturnService(dbB);

      final input = SupplierReturnPostingInput(
        supplierId: supplierId,
        purchaseInvoiceId: invoiceId,
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 7,
          ),
        ],
      );

      final stockBefore = await productStock(dbA);
      expect(stockBefore, closeTo(14, 0.001));

      final outcomes = await Future.wait<Object?>([
        runConcurrentReturn(serviceA, input),
        runConcurrentReturn(serviceB, input),
      ]);

      final successes = outcomes.whereType<int>();
      final failures = outcomes.whereType<SupplierReturnPostingFailure>();

      expect(successes.length, 1);
      expect(failures.length, 1);
      expect(
        failures.single,
        SupplierReturnPostingFailure.quantityExceedsReturnable,
      );

      expect(await returnedQuantity(dbA), 7);
      expect(await returnHeaderCount(dbA), 1);
      expect(await returnItemCount(dbA), 1);
      expect(await supplierReturnTxnCount(dbA), 1);
      expect(await returnOutCount(dbA), 1);
      expect(await productStock(dbA), closeTo(stockBefore - 7, 0.001));
    });

    test('B) sequential 6 + 4 succeeds with total returned 10', () async {
      await service.postPurchaseLinkedReturn(postingInput(quantity: 6));
      await service.postPurchaseLinkedReturn(postingInput(quantity: 4));

      expect(await returnedQuantity(), 10);
      expect(await returnHeaderCount(), 2);
      expect(await supplierReturnTxnCount(), 2);
    });

    test('C) sequential 10 + 1 allows only 10 total returned', () async {
      await service.postPurchaseLinkedReturn(postingInput(quantity: 10));

      await expectLater(
        service.postPurchaseLinkedReturn(postingInput(quantity: 1)),
        throwsA(
          isA<SupplierReturnPostingException>().having(
            (e) => e.code,
            'code',
            SupplierReturnPostingFailure.quantityExceedsReturnable,
          ),
        ),
      );

      expect(await returnedQuantity(), 10);
      expect(await returnHeaderCount(), 1);
    });

    test('D) 11 against 10 rejected with no side effects', () async {
      final stockBefore = await productStock();
      final balanceBefore =
          await db.supplierAccountsDao.getBalance(supplierId);

      await expectLater(
        service.postPurchaseLinkedReturn(postingInput(quantity: 11)),
        throwsA(
          isA<SupplierReturnPostingException>().having(
            (e) => e.code,
            'code',
            SupplierReturnPostingFailure.quantityExceedsReturnable,
          ),
        ),
      );

      expect(await returnedQuantity(), 0);
      expect(await returnHeaderCount(), 0);
      expect(await returnItemCount(), 0);
      expect(await returnOutCount(), 0);
      expect(await supplierReturnTxnCount(), 0);
      expect(await productStock(), stockBefore);
      expect(await db.supplierAccountsDao.getBalance(supplierId), balanceBefore);
    });

    test('E) exact remaining quantity succeeds after partial return', () async {
      await service.postPurchaseLinkedReturn(postingInput(quantity: 7));
      await service.postPurchaseLinkedReturn(postingInput(quantity: 3));

      expect(await returnedQuantity(), 10);
      expect(await returnHeaderCount(), 2);
    });

    test('F) multiple return documents 7 + 3 both succeed', () async {
      await service.postPurchaseLinkedReturn(postingInput(quantity: 7));
      await service.postPurchaseLinkedReturn(postingInput(quantity: 3));

      expect(await returnedQuantity(), 10);
      expect(await returnHeaderCount(), 2);
      expect(await returnItemCount(), 2);
      expect(await supplierReturnTxnCount(), 2);
    });

    test('G) losing concurrent transaction leaves no orphan mutations',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}sr23g_${DateTime.now().microsecondsSinceEpoch}.db';
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
      await seedPurchase(target: dbA, initialStock: 4);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = SupplierReturnService(dbA);
      final serviceB = SupplierReturnService(dbB);
      final input = SupplierReturnPostingInput(
        supplierId: supplierId,
        purchaseInvoiceId: invoiceId,
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 7,
          ),
        ],
      );
      final stockBefore = await productStock(dbA);
      final balanceBefore =
          await dbA.supplierAccountsDao.getBalance(supplierId);

      final outcomes = await Future.wait<Object?>([
        runConcurrentReturn(serviceA, input),
        runConcurrentReturn(serviceB, input),
      ]);

      expect(outcomes.whereType<int>().length, 1);
      expect(
        outcomes.whereType<SupplierReturnPostingFailure>().single,
        SupplierReturnPostingFailure.quantityExceedsReturnable,
      );

      expect(await returnHeaderCount(dbA), 1);
      expect(await returnItemCount(dbA), 1);
      expect(await returnOutCount(dbA), 1);
      expect(await supplierReturnTxnCount(dbA), 1);
      expect(await returnedQuantity(dbA), 7);
      expect(await productStock(dbA), closeTo(stockBefore - 7, 0.001));
      expect(await dbA.supplierAccountsDao.getBalance(supplierId),
          closeTo(balanceBefore - 35, 0.001));
    });
  });
}