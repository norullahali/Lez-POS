import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/opening_stock_live_activity_exception.dart';
import 'package:lez_pos/core/services/opening_stock_save_fingerprint.dart';
import 'package:lez_pos/core/services/opening_stock_save_service.dart';
import 'package:lez_pos/core/services/pos_sale_fingerprint.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/purchase_fingerprint.dart';
import 'package:lez_pos/core/services/purchase_save_service.dart';
import 'package:lez_pos/core/services/stock_adjustment_save_fingerprint.dart';
import 'package:lez_pos/core/services/stock_adjustment_save_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/stock_adjustment_save_result.dart';
import 'package:lez_pos/core/services/stock_adjustment_save_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/pos/models/cart_item.dart';
import 'package:lez_pos/features/products/models/product_model.dart';
import 'package:lez_pos/features/returns/models/supplier_return_draft_models.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uuid/uuid.dart';

import 'support/customer_quick_return_test_keys.dart';
import 'support/stock_adjustment_save_test_keys.dart';
import 'support/supplier_return_posting_helpers.dart';
import 'support/supplier_return_test_keys.dart';

const _b21SaleUuid = Uuid();
String b21SaleIdempotencyKey() => _b21SaleUuid.v4();

Future<({sqlite3.Database rawDb, String path})> openSimulatedV47RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b21_v47_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement('DROP TABLE IF EXISTS stock_adjustment_idempotency');
  await bootstrap.customStatement('DROP INDEX IF EXISTS sai_stock_adjustment_idx');
  await bootstrap.customStatement('PRAGMA user_version = 47');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 47);
  return (rawDb: rawDb, path: dbPath);
}

Future<({
  AppDatabase dbA,
  AppDatabase dbB,
  sqlite3.Database rawA,
  sqlite3.Database rawB,
  String path,
})> openDualConnectionRaceDatabases() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b21_race_${DateTime.now().microsecondsSinceEpoch}.db';
  final rawA = sqlite3.sqlite3.open(dbPath);
  final rawB = sqlite3.sqlite3.open(dbPath);
  rawA.execute('PRAGMA busy_timeout = 15000');
  rawB.execute('PRAGMA busy_timeout = 15000');
  final dbA = AppDatabase.test(NativeDatabase.opened(rawA));
  final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
  return (
    dbA: dbA,
    dbB: dbB,
    rawA: rawA,
    rawB: rawB,
    path: dbPath,
  );
}

void disposeDualConnectionRaceDatabases(
  ({
    AppDatabase dbA,
    AppDatabase dbB,
    sqlite3.Database rawA,
    sqlite3.Database rawB,
    String path,
  }) opened,
) {
  opened.rawA.dispose();
  opened.rawB.dispose();
  File(opened.path).deleteSync();
}

void main() {
  late AppDatabase db;
  late StockAdjustmentSaveService service;
  late int userId;
  late int productId;

  setUp(() async {
    db = AppDatabase.test();
    service = StockAdjustmentSaveService(db);
    userId = await db.into(db.usersTable).insert(
          UsersTableCompanion.insert(
            fullName: 'B21 User',
            username: 'b21_${DateTime.now().microsecondsSinceEpoch}',
            passwordHash: 'hash',
            roleId: 1,
          ),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B21 Product A'),
            barcode: Value('B21-A'),
            currentStock: Value(10),
            costPrice: Value(5),
            sellPrice: Value(10),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  String fingerprintFor({
    int? pid,
    double quantityChange = 5,
    String adjustmentType = 'CORRECTION',
    String reason = 'B21 reason',
    String note = '',
    int? createdByOverride,
  }) {
    return StockAdjustmentSaveFingerprint.compute(
      productId: pid ?? productId,
      quantityChange: quantityChange,
      adjustmentType: adjustmentType,
      reason: reason,
      note: note,
      createdBy: createdByOverride ?? userId,
    );
  }

  Future<StockAdjustmentSaveResult> saveAdjustment({
    StockAdjustmentSaveService? targetService,
    required String idempotencyKey,
    int? pid,
    double quantityChange = 5,
    String adjustmentType = 'CORRECTION',
    String reason = 'B21 reason',
    String note = '',
    String? fingerprint,
    int? createdByOverride,
  }) {
    final svc = targetService ?? service;
    final fp = fingerprint ??
        fingerprintFor(
          pid: pid,
          quantityChange: quantityChange,
          adjustmentType: adjustmentType,
          reason: reason,
          note: note,
          createdByOverride: createdByOverride,
        );
    return svc.processSave(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      productId: pid ?? productId,
      quantityChange: quantityChange,
      adjustmentType: adjustmentType,
      reason: reason,
      note: note,
      createdBy: createdByOverride ?? userId,
    );
  }

  Future<int> adjustmentCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.stockAdjustments).get()).length;
  }

  Future<int> idempotencyCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.stockAdjustmentIdempotency).get()).length;
  }

  Future<int> adjustmentLedgerCount([AppDatabase? database, int? pid]) async {
    final target = database ?? db;
    if (pid != null) {
      final rows = await target.customSelect(
        "SELECT COUNT(*) AS cnt FROM stock_ledger WHERE product_id = ? AND movement_type = 'ADJUSTMENT'",
        variables: [Variable.withInt(pid)],
      ).getSingle();
      return rows.data['cnt'] as int;
    }
    final rows = await target.customSelect(
      "SELECT COUNT(*) AS cnt FROM stock_ledger WHERE movement_type = 'ADJUSTMENT'",
    ).getSingle();
    return rows.data['cnt'] as int;
  }

  Future<int> activityLogCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.activityLogs)
          ..where((l) => l.activityType.equals('inventory.stock.adjusted')))
        .get())
        .length;
  }

  Future<double> productStock(int pid, [AppDatabase? database]) async {
    final target = database ?? db;
    final row = await (target.select(target.products)..where((p) => p.id.equals(pid)))
        .getSingle();
    return row.currentStock;
  }

  Future<void> recordSale(int pid, {double qty = 1, AppDatabase? database}) async {
    final target = database ?? db;
    final saleService = PosSaleService(target);
    final paymentKey = b21SaleIdempotencyKey();
    final product = ProductModel(
      id: pid,
      name: 'Sale Product',
      barcode: 'SALE-$pid',
      costPrice: 5,
      sellPrice: 10,
    );
    final fp = PosSaleFingerprint.compute(
      sessionId: 1,
      cartSlotId: 1,
      items: [CartItem(product: product, quantity: qty, unitPrice: 10)],
      invoiceDiscount: 0,
      loyaltyPointsUsed: 0,
      loyaltyDiscount: 0,
      customerId: null,
      payment: PaymentInfo(method: 'CASH', idempotencyKey: paymentKey, cashPaid: 10 * qty),
    );
    await saleService.processSale(
      idempotencyKey: paymentKey,
      fingerprintHash: fp,
      invoice: SalesInvoicesCompanion(
        subtotal: Value(10 * qty),
        total: Value(10 * qty),
        paymentMethod: const Value('CASH'),
        cashPaid: Value(10 * qty),
        debtAmount: const Value(0),
      ),
      items: [
        SaleItemsCompanion(
          productId: Value(pid),
          quantity: Value(qty),
          unitPrice: const Value(10),
          unitCost: const Value(5),
          total: Value(10 * qty),
        ),
      ],
    );
  }

  Future<void> recordPurchase(int pid, {AppDatabase? database, int? supplierOverride}) async {
    final target = database ?? db;
    final purchaseService = PurchaseSaveService(target);
    final sid = supplierOverride ??
        await target.into(target.suppliers).insert(
              const SuppliersCompanion(name: Value('B21 Supplier')),
            );
    final key = b21StockAdjustmentSaveIdempotencyKey();
    final purchaseDate = DateTime(2026, 10, 1);
    final fp = PurchaseFingerprint.compute(
      supplierId: sid,
      operatorInvoiceNumber: null,
      purchaseDate: purchaseDate,
      invoiceDiscount: 0,
      total: 100,
      paidAmount: 0,
      dueDate: null,
      notes: '',
      items: [
        PurchaseFingerprintLine(productId: pid, quantity: 10, unitCost: 10),
      ],
    );
    await purchaseService.processSave(
      idempotencyKey: key,
      fingerprintHash: fp,
      supplierId: sid,
      operatorInvoiceNumber: '',
      purchaseDate: purchaseDate,
      invoiceDiscount: 0,
      total: 100,
      paidAmount: 0,
      dueDate: null,
      notes: '',
      items: [
        {'productId': pid, 'qty': 10, 'cost': 10, 'discount': 0.0},
      ],
    );
  }

  Future<void> recordQuickReturn(int pid, {AppDatabase? database, int? uid}) async {
    final target = database ?? db;
    await PosSaleService(target).processQuickReturn(
      idempotencyKey: b9QuickReturnIdempotencyKey(),
      productId: pid,
      quantity: 1,
      refundAmount: 10,
      userId: uid ?? userId,
      reason: 'B21 quick return',
    );
  }

  Future<({
    int supplierId,
    int invoiceId,
    int purchaseItemId,
  })> setupSupplierReturnPurchase(int pid, AppDatabase database) async {
    final sid = await database.into(database.suppliers).insert(
          const SuppliersCompanion(name: Value('B21 Return Supplier')),
        );
    await recordPurchase(pid, database: database, supplierOverride: sid);
    final invoice = await (database.select(database.purchaseInvoices)
          ..where((p) => p.supplierId.equals(sid)))
        .getSingle();
    final item = await (database.select(database.purchaseItems)
          ..where((i) => i.invoiceId.equals(invoice.id)))
        .getSingle();
    return (supplierId: sid, invoiceId: invoice.id, purchaseItemId: item.id);
  }

  group('B21 stock adjustment save protection', () {
    test('1) first save succeeds', () async {
      final key = b21StockAdjustmentSaveIdempotencyKey();
      final result = await saveAdjustment(idempotencyKey: key);

      expect(result.idempotentReplay, isFalse);
      expect(result.stockAdjustmentId, greaterThan(0));
      expect(await adjustmentCount(), 1);
      expect(await idempotencyCount(), 1);
      expect(await adjustmentLedgerCount(), 1);
      expect(await activityLogCount(), 1);
      expect(await productStock(productId), 15);
    });

    test('2) same key + same fingerprint replay', () async {
      final key = b21StockAdjustmentSaveIdempotencyKey();
      final fp = fingerprintFor();
      final first = await saveAdjustment(idempotencyKey: key, fingerprint: fp);
      final stockAfterFirst = await productStock(productId);
      final second = await saveAdjustment(idempotencyKey: key, fingerprint: fp);

      expect(second.idempotentReplay, isTrue);
      expect(second.stockAdjustmentId, first.stockAdjustmentId);
      expect(await adjustmentCount(), 1);
      expect(await productStock(productId), stockAfterFirst);
    });

    test('3) same key + different fingerprint conflict', () async {
      final key = b21StockAdjustmentSaveIdempotencyKey();
      await saveAdjustment(idempotencyKey: key, quantityChange: 5);

      await expectLater(
        saveAdjustment(idempotencyKey: key, quantityChange: 10),
        throwsA(isA<StockAdjustmentSaveIdempotencyConflictException>()),
      );

      expect(await adjustmentCount(), 1);
      expect(await productStock(productId), 15);
    });

    test('4) sequential duplicate same key', () async {
      final key = b21StockAdjustmentSaveIdempotencyKey();
      final fp = fingerprintFor();
      await saveAdjustment(idempotencyKey: key, fingerprint: fp);
      await saveAdjustment(idempotencyKey: key, fingerprint: fp);
      expect(await adjustmentCount(), 1);
    });

    test('5) different keys legitimate adjustments', () async {
      await saveAdjustment(
        idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        quantityChange: 3,
      );
      await saveAdjustment(
        idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        quantityChange: 2,
      );
      expect(await adjustmentCount(), 2);
      expect(await productStock(productId), 15);
    });

    test('6) rollback after adjustment and ledger write', () async {
      final flaky = StockAdjustmentSaveService(
        db,
        testActivityLogHook: () async {
          throw StateError('forced post-write failure');
        },
      );

      await expectLater(
        saveAdjustment(
          targetService: flaky,
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await adjustmentCount(), 0);
      expect(await adjustmentLedgerCount(), 0);
      expect(await idempotencyCount(), 0);
      expect(await activityLogCount(), 0);
      expect(await productStock(productId), 10);
    });

    test('7) rollback after activity log failure', () async {
      await db.customStatement('''
        CREATE TRIGGER b21_block_activity_log
        BEFORE INSERT ON activity_logs
        BEGIN
          SELECT RAISE(FAIL, 'forced activity log failure');
        END;
      ''');

      await expectLater(
        saveAdjustment(idempotencyKey: b21StockAdjustmentSaveIdempotencyKey()),
        throwsA(isA<Exception>()),
      );

      expect(await adjustmentCount(), 0);
      expect(await idempotencyCount(), 0);
      expect(await productStock(productId), 10);
    });

    test('8) createdBy <= 0 rejected with zero mutation', () async {
      await expectLater(
        service.processSave(
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
          fingerprintHash: 'ignored-for-auth-test',
          productId: productId,
          quantityChange: 5,
          adjustmentType: 'CORRECTION',
          reason: 'auth test',
          createdBy: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await adjustmentCount(), 0);
      expect(await idempotencyCount(), 0);
      expect(await productStock(productId), 10);
    });

    test('9) zero delta rejected before mutation', () async {
      await expectLater(
        saveAdjustment(
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
          quantityChange: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await adjustmentCount(), 0);
      expect(await idempotencyCount(), 0);
      expect(await productStock(productId), 10);
    });

    test('10) missing/inactive product rejected', () async {
      await expectLater(
        saveAdjustment(
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
          pid: 999999,
        ),
        throwsA(isA<StateError>()),
      );

      final inactiveId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Inactive Product'),
              isActive: Value(false),
              currentStock: Value(5),
            ),
          );

      await expectLater(
        saveAdjustment(
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
          pid: inactiveId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('11) concurrent same-key + same fingerprint', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Race User',
              username: 'race_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Race Product'),
              currentStock: Value(10),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      final releaseWinner = Completer<void>();
      final serviceA = StockAdjustmentSaveService(
        opened.dbA,
        preSealHook: () async => releaseWinner.future,
      );
      final serviceB = StockAdjustmentSaveService(opened.dbB);
      final sameKey = b21StockAdjustmentSaveIdempotencyKey();
      final fp = StockAdjustmentSaveFingerprint.compute(
        productId: pid,
        quantityChange: 5,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        note: '',
        createdBy: uid,
      );

      final futureA = serviceA.processSave(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        productId: pid,
        quantityChange: 5,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        createdBy: uid,
      );
      final futureB = serviceB.processSave(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        productId: pid,
        quantityChange: 5,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        createdBy: uid,
      );

      releaseWinner.complete();
      final outcomes = await Future.wait<StockAdjustmentSaveResult>([
        futureA,
        futureB,
      ]);

      expect(await adjustmentCount(opened.dbA), 1);
      expect(await idempotencyCount(opened.dbA), 1);
      expect(await adjustmentLedgerCount(opened.dbA, pid), 1);
      expect(await activityLogCount(opened.dbA), 1);
      expect(outcomes.map((r) => r.stockAdjustmentId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
      expect(await productStock(pid, opened.dbA), 15);
    });

    test('12) concurrent different-key same product', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Diff Key User',
              username: 'dk_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Diff Key Product'),
              currentStock: Value(10),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      final serviceA = StockAdjustmentSaveService(opened.dbA);
      final serviceB = StockAdjustmentSaveService(opened.dbB);
      final fpA = StockAdjustmentSaveFingerprint.compute(
        productId: pid,
        quantityChange: 3,
        adjustmentType: 'CORRECTION',
        reason: 'a',
        note: '',
        createdBy: uid,
      );
      final fpB = StockAdjustmentSaveFingerprint.compute(
        productId: pid,
        quantityChange: 2,
        adjustmentType: 'CORRECTION',
        reason: 'b',
        note: '',
        createdBy: uid,
      );

      await Future.wait([
        serviceA.processSave(
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
          fingerprintHash: fpA,
          productId: pid,
          quantityChange: 3,
          adjustmentType: 'CORRECTION',
          reason: 'a',
          createdBy: uid,
        ),
        serviceB.processSave(
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
          fingerprintHash: fpB,
          productId: pid,
          quantityChange: 2,
          adjustmentType: 'CORRECTION',
          reason: 'b',
          createdBy: uid,
        ),
      ]);

      expect(await adjustmentCount(opened.dbA), 2);
      expect(await idempotencyCount(opened.dbA), 2);
      expect(await productStock(pid, opened.dbA), 15);
    });

    test('13) adjustment vs sale concurrency', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Adj Sale User',
              username: 'as_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Adj Sale Product'),
              currentStock: Value(20),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      const adjustmentQty = 5.0;
      const saleQty = 2.0;
      final adjustmentAtBarrier = Completer<void>();
      final releaseAdjustment = Completer<void>();

      final adjustmentService = StockAdjustmentSaveService(
        opened.dbA,
        beforeAdjustmentHook: () async {
          if (!adjustmentAtBarrier.isCompleted) adjustmentAtBarrier.complete();
          await releaseAdjustment.future;
        },
      );
      final fp = StockAdjustmentSaveFingerprint.compute(
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        note: '',
        createdBy: uid,
      );

      final adjustmentFuture = adjustmentService.processSave(
        idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        fingerprintHash: fp,
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        createdBy: uid,
      );

      await adjustmentAtBarrier.future;
      await recordSale(pid, qty: saleQty, database: opened.dbB);
      releaseAdjustment.complete();
      await adjustmentFuture;

      expect(await adjustmentCount(opened.dbA), 1);
      expect(await idempotencyCount(opened.dbA), 1);
      expect(await productStock(pid, opened.dbA), 20 + adjustmentQty - saleQty);
    });

    test('14) adjustment vs purchase concurrency', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Adj Purchase User',
              username: 'ap_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Adj Purchase Product'),
              currentStock: Value(10),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      const adjustmentQty = -3.0;
      const purchaseQty = 10.0;
      final adjustmentAtBarrier = Completer<void>();
      final releaseAdjustment = Completer<void>();

      final adjustmentService = StockAdjustmentSaveService(
        opened.dbA,
        beforeAdjustmentHook: () async {
          if (!adjustmentAtBarrier.isCompleted) adjustmentAtBarrier.complete();
          await releaseAdjustment.future;
        },
      );
      final fp = StockAdjustmentSaveFingerprint.compute(
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        note: '',
        createdBy: uid,
      );

      final adjustmentFuture = adjustmentService.processSave(
        idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        fingerprintHash: fp,
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        createdBy: uid,
      );

      await adjustmentAtBarrier.future;
      await recordPurchase(pid, database: opened.dbB);
      releaseAdjustment.complete();
      await adjustmentFuture;

      expect(await adjustmentCount(opened.dbA), 1);
      expect(await productStock(pid, opened.dbA), 10 + adjustmentQty + purchaseQty);
    });

    test('15) adjustment vs customer return concurrency', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Adj Return User',
              username: 'ar_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Adj Return Product'),
              currentStock: Value(10),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      const adjustmentQty = -2.0;
      const returnQty = 1.0;
      final adjustmentAtBarrier = Completer<void>();
      final releaseAdjustment = Completer<void>();

      final adjustmentService = StockAdjustmentSaveService(
        opened.dbA,
        beforeAdjustmentHook: () async {
          if (!adjustmentAtBarrier.isCompleted) adjustmentAtBarrier.complete();
          await releaseAdjustment.future;
        },
      );
      final fp = StockAdjustmentSaveFingerprint.compute(
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        note: '',
        createdBy: uid,
      );

      final adjustmentFuture = adjustmentService.processSave(
        idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        fingerprintHash: fp,
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        createdBy: uid,
      );

      await adjustmentAtBarrier.future;
      await recordQuickReturn(pid, database: opened.dbB, uid: uid);
      releaseAdjustment.complete();
      await adjustmentFuture;

      expect(await adjustmentCount(opened.dbA), 1);
      expect(await productStock(pid, opened.dbA), 10 + adjustmentQty + returnQty);
    });

    test('16) adjustment vs supplier return concurrency', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Adj Supplier Return User',
              username: 'asr_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Adj Supplier Return Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
      final purchase = await setupSupplierReturnPurchase(pid, opened.dbA);
      expect(await productStock(pid, opened.dbA), 10);

      const adjustmentQty = 4.0;
      const returnQty = 2.0;
      final adjustmentAtBarrier = Completer<void>();
      final releaseAdjustment = Completer<void>();

      final adjustmentService = StockAdjustmentSaveService(
        opened.dbA,
        beforeAdjustmentHook: () async {
          if (!adjustmentAtBarrier.isCompleted) adjustmentAtBarrier.complete();
          await releaseAdjustment.future;
        },
      );
      final fp = StockAdjustmentSaveFingerprint.compute(
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        note: '',
        createdBy: uid,
      );

      final adjustmentFuture = adjustmentService.processSave(
        idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        fingerprintHash: fp,
        productId: pid,
        quantityChange: adjustmentQty,
        adjustmentType: 'CORRECTION',
        reason: 'race',
        createdBy: uid,
      );

      await adjustmentAtBarrier.future;
      final serviceB = SupplierReturnService(opened.dbB);
      await postSupplierReturn(
        serviceB,
        SupplierReturnPostingInput(
          supplierId: purchase.supplierId,
          purchaseInvoiceId: purchase.invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchase.purchaseItemId,
              quantity: returnQty,
            ),
          ],
        ),
        idempotencyKey: b15SupplierReturnIdempotencyKey(),
      );
      releaseAdjustment.complete();
      await adjustmentFuture;

      expect(await adjustmentCount(opened.dbA), 1);
      expect(await productStock(pid, opened.dbA), 10 + adjustmentQty - returnQty);
    });

    test('17) adjustment before opening blocks opening', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Adj Opening User',
              username: 'ao_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Adj Opening Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      await StockAdjustmentSaveService(opened.dbB).processSave(
        idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
        fingerprintHash: StockAdjustmentSaveFingerprint.compute(
          productId: pid,
          quantityChange: 5,
          adjustmentType: 'CORRECTION',
          reason: 'first',
          note: '',
          createdBy: uid,
        ),
        productId: pid,
        quantityChange: 5,
        adjustmentType: 'CORRECTION',
        reason: 'first',
        createdBy: uid,
      );
      expect(await productStock(pid, opened.dbA), 5);

      final openingService = OpeningStockSaveService(opened.dbA);
      final products = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 100, unitCost: 5),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      Object? outcome;
      try {
        await openingService.processSave(
          idempotencyKey: b21StockAdjustmentSaveIdempotencyKey(),
          fingerprintHash: fp,
          products: products,
          createdBy: uid,
        );
      } catch (e) {
        outcome = e;
      }

      expect(outcome, isA<OpeningStockLiveActivityException>());
      expect(await productStock(pid, opened.dbA), 5);
    });

    test('18) migration v47 -> v48 creates stock_adjustment_idempotency', () async {
      final opened = await openSimulatedV47RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='stock_adjustment_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 48);
      final tables = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='stock_adjustment_idempotency'",
      ).get();
      expect(tables.length, 1);
    });

    test('19) replay produces zero additional stock delta', () async {
      final key = b21StockAdjustmentSaveIdempotencyKey();
      final fp = fingerprintFor(quantityChange: 7);
      await saveAdjustment(idempotencyKey: key, fingerprint: fp, quantityChange: 7);
      final stockAfterFirst = await productStock(productId);

      await saveAdjustment(idempotencyKey: key, fingerprint: fp, quantityChange: 7);
      expect(await productStock(productId), stockAfterFirst);
    });

    test('20) replay produces zero duplicate rows', () async {
      final key = b21StockAdjustmentSaveIdempotencyKey();
      final fp = fingerprintFor();
      await saveAdjustment(idempotencyKey: key, fingerprint: fp);
      final adjAfterFirst = await adjustmentCount();
      final ledgerAfterFirst = await adjustmentLedgerCount();
      final logsAfterFirst = await activityLogCount();
      final idemAfterFirst = await idempotencyCount();

      await saveAdjustment(idempotencyKey: key, fingerprint: fp);

      expect(await adjustmentCount(), adjAfterFirst);
      expect(await adjustmentLedgerCount(), ledgerAfterFirst);
      expect(await activityLogCount(), logsAfterFirst);
      expect(await idempotencyCount(), idemAfterFirst);
    });

    test('20b) idempotency seal failure rolls back complete adjustment', () async {
      final flaky = StockAdjustmentSaveService(
        db,
        preSealHook: () async {
          throw StateError('forced seal failure');
        },
      );
      final key = b21StockAdjustmentSaveIdempotencyKey();
      final fp = fingerprintFor();

      await expectLater(
        saveAdjustment(
          targetService: flaky,
          idempotencyKey: key,
          fingerprint: fp,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await adjustmentCount(), 0);
      expect(await idempotencyCount(), 0);
      expect(await productStock(productId), 10);

      final retry = await saveAdjustment(idempotencyKey: key, fingerprint: fp);
      expect(retry.idempotentReplay, isFalse);
      expect(await adjustmentCount(), 1);
      expect(await idempotencyCount(), 1);
    });

    test('20c) real idempotency PK constraint and processSave replay', () async {
      final key = b21StockAdjustmentSaveIdempotencyKey();
      final fp = fingerprintFor();

      await db.stockAdjustmentIdempotencyDao.insertCompletedRecord(
        idempotencyKey: key,
        fingerprintHash: fp,
        stockAdjustmentId: 1,
      );

      await expectLater(
        db.stockAdjustmentIdempotencyDao.insertCompletedRecord(
          idempotencyKey: key,
          fingerprintHash: fp,
          stockAdjustmentId: 2,
        ),
        throwsA(
          predicate<SqliteException>(
            (e) =>
                e.extendedResultCode == 1555 ||
                e.extendedResultCode == 2067,
          ),
        ),
      );

      final result = await saveAdjustment(idempotencyKey: key, fingerprint: fp);
      expect(result.idempotentReplay, isTrue);
      expect(result.stockAdjustmentId, 1);
      expect(await idempotencyCount(), 1);
      expect(await adjustmentCount(), 0);
    });
  });
}
