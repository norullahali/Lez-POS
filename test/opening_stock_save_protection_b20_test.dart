import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/opening_stock_live_activity_exception.dart';
import 'package:lez_pos/core/services/opening_stock_product_already_opened_exception.dart';
import 'package:lez_pos/core/services/opening_stock_save_fingerprint.dart';
import 'package:lez_pos/core/services/opening_stock_save_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/opening_stock_save_result.dart';
import 'package:lez_pos/core/services/opening_stock_save_service.dart';
import 'package:lez_pos/core/services/pos_sale_fingerprint.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/purchase_fingerprint.dart';
import 'package:lez_pos/core/services/purchase_save_service.dart';
import 'package:lez_pos/features/pos/models/cart_item.dart';
import 'package:lez_pos/features/products/models/product_model.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uuid/uuid.dart';

import 'support/opening_stock_save_test_keys.dart';

const _b20SaleUuid = Uuid();
String b20SaleIdempotencyKey() => _b20SaleUuid.v4();

Future<({sqlite3.Database rawDb, String path})> openSimulatedV46RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b20_v46_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement('DROP TABLE IF EXISTS opening_stock_idempotency');
  await bootstrap.customStatement('DROP TABLE IF EXISTS product_opening_stock_seals');
  await bootstrap.customStatement('PRAGMA user_version = 46');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 46);
  return (rawDb: rawDb, path: dbPath);
}


Future<Object?> captureSaveOutcome(Future<OpeningStockSaveResult> future) async {
  try {
    return await future;
  } catch (e) {
    return e;
  }
}

Future<Object?> captureVoidOutcome(Future<void> future) async {
  try {
    await future;
    return null;
  } catch (e) {
    return e;
  }
}

Future<({
  AppDatabase dbA,
  AppDatabase dbB,
  sqlite3.Database rawA,
  sqlite3.Database rawB,
  String path,
})> openDualConnectionRaceDatabases() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b20_race_${DateTime.now().microsecondsSinceEpoch}.db';
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
  late OpeningStockSaveService service;
  late int userId;
  late int productId;
  late int productId2;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.test();
    service = OpeningStockSaveService(db);
    userId = await db.into(db.usersTable).insert(
          UsersTableCompanion.insert(
            fullName: 'B20 User',
            username: 'b20_${DateTime.now().microsecondsSinceEpoch}',
            passwordHash: 'hash',
            roleId: 1,
          ),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B20 Product A'),
            barcode: Value('B20-A'),
            currentStock: Value(0),
            costPrice: Value(5),
            sellPrice: Value(10),
          ),
        );
    productId2 = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B20 Product B'),
            barcode: Value('B20-B'),
            currentStock: Value(0),
            costPrice: Value(3),
            sellPrice: Value(8),
          ),
        );
    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('B20 Supplier')),
        );
  });

  tearDown(() async {
    await db.close();
  });

  List<OpeningStockFingerprintProduct> defaultProducts({
    double qty = 50,
    double cost = 5,
    int? pid,
    int? pid2,
    double qty2 = 30,
    double cost2 = 3,
  }) {
    return [
      OpeningStockFingerprintProduct(
        productId: pid ?? productId,
        quantity: qty,
        unitCost: cost,
      ),
      OpeningStockFingerprintProduct(
        productId: pid2 ?? productId2,
        quantity: qty2,
        unitCost: cost2,
      ),
    ];
  }

  String fingerprintFor({
    List<OpeningStockFingerprintProduct>? products,
    int? createdByOverride,
  }) {
    return OpeningStockSaveFingerprint.compute(
      products: products ?? defaultProducts(),
      createdBy: createdByOverride ?? userId,
    );
  }

  Future<OpeningStockSaveResult> saveOpening({
    OpeningStockSaveService? targetService,
    required String idempotencyKey,
    List<OpeningStockFingerprintProduct>? products,
    String? fingerprint,
    int? createdByOverride,
  }) {
    final svc = targetService ?? service;
    final fp = fingerprint ??
        fingerprintFor(
          products: products,
          createdByOverride: createdByOverride,
        );
    return svc.processSave(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      products: products ?? defaultProducts(),
      createdBy: createdByOverride ?? userId,
    );
  }

  Future<int> sealCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.productOpeningStockSeals).get()).length;
  }

  Future<int> bulkIdempotencyCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.openingStockIdempotency).get()).length;
  }

  Future<int> openingLedgerCount([AppDatabase? database, int? pid]) async {
    final target = database ?? db;
    if (pid != null) {
      final rows = await target.customSelect(
        "SELECT COUNT(*) AS cnt FROM stock_ledger WHERE product_id = ? AND movement_type = 'OPENING'",
        variables: [Variable.withInt(pid)],
      ).getSingle();
      return rows.data['cnt'] as int;
    }
    final rows = await target.customSelect(
      "SELECT COUNT(*) AS cnt FROM stock_ledger WHERE movement_type = 'OPENING'",
    ).getSingle();
    return rows.data['cnt'] as int;
  }

  Future<int> openingLogCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.logsTable)
          ..where((l) => l.actionType.equals('OPENING_STOCK_SAVE')))
        .get())
        .length;
  }

  Future<int> liveLedgerCount([AppDatabase? database, int? pid]) async {
    final target = database ?? db;
    if (pid != null) {
      final rows = await target.customSelect(
        "SELECT COUNT(*) AS cnt FROM stock_ledger WHERE product_id = ? AND movement_type != 'OPENING'",
        variables: [Variable.withInt(pid)],
      ).getSingle();
      return rows.data['cnt'] as int;
    }
    final rows = await target.customSelect(
      "SELECT COUNT(*) AS cnt FROM stock_ledger WHERE movement_type != 'OPENING'",
    ).getSingle();
    return rows.data['cnt'] as int;
  }

  Future<int> movementCount([AppDatabase? database, int? pid]) async {
    final target = database ?? db;
    if (pid != null) {
      final rows = await target.customSelect(
        'SELECT COUNT(*) AS cnt FROM stock_movements WHERE product_id = ?',
        variables: [Variable.withInt(pid)],
      ).getSingle();
      return rows.data['cnt'] as int;
    }
    final rows = await target.customSelect(
      'SELECT COUNT(*) AS cnt FROM stock_movements',
    ).getSingle();
    return rows.data['cnt'] as int;
  }

  Future<double> productStock(int pid, [AppDatabase? database]) async {
    final target = database ?? db;
    final row = await (target.select(target.products)
          ..where((p) => p.id.equals(pid)))
        .getSingle();
    return row.currentStock;
  }

  Future<void> expectZeroOpeningState({
    required AppDatabase database,
    required int productId,
  }) async {
    expect(await sealCount(database), 0);
    expect(await bulkIdempotencyCount(database), 0);
    expect(await openingLedgerCount(database, productId), 0);
    expect(await movementCount(database, productId), 0);
    expect(await openingLogCount(database), 0);
  }

  Future<void> recordSale(int pid, {double qty = 1, AppDatabase? database}) async {
    final target = database ?? db;
    final saleService = PosSaleService(target);
    final paymentKey = b20SaleIdempotencyKey();
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

  Future<void> recordPurchase(int pid, {AppDatabase? database}) async {
    final target = database ?? db;
    final purchaseService = PurchaseSaveService(target);
    final key = b20OpeningStockSaveIdempotencyKey();
    final purchaseDate = DateTime(2026, 10, 1);
    final fp = PurchaseFingerprint.compute(
      supplierId: supplierId,
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
      supplierId: supplierId,
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

  Future<void> recordAdjustment(
    int pid, {
    AppDatabase? database,
    int? createdByUserId,
  }) async {
    final target = database ?? db;
    await target.stockDao.createAdjustment(
      productId: pid,
      quantityChange: 5,
      adjustmentType: 'increase',
      reason: 'B20 test adjustment',
      createdByUserId: createdByUserId ?? userId,
    );
  }

  group('B20 opening stock save protection', () {
    test('1) first bulk opening save', () async {
      final key = b20OpeningStockSaveIdempotencyKey();
      final result = await saveOpening(idempotencyKey: key);

      expect(result.idempotentReplay, isFalse);
      expect(result.sealedProductIds, [productId, productId2]);
      expect(await sealCount(), 2);
      expect(await bulkIdempotencyCount(), 1);
      expect(await openingLedgerCount(), 2);
      expect(await openingLogCount(), 1);
      expect(await productStock(productId), 50);
      expect(await productStock(productId2), 30);
    });

    test('2) same key + same fingerprint replay', () async {
      final key = b20OpeningStockSaveIdempotencyKey();
      final fp = fingerprintFor();
      final first = await saveOpening(idempotencyKey: key, fingerprint: fp);
      final ledgerAfterFirst = await openingLedgerCount();
      final movementsAfterFirst = await movementCount();
      final stockA = await productStock(productId);
      final stockB = await productStock(productId2);
      final logsAfterFirst = await openingLogCount();

      final second = await saveOpening(idempotencyKey: key, fingerprint: fp);

      expect(second.idempotentReplay, isTrue);
      expect(await sealCount(), 2);
      expect(await openingLedgerCount(), ledgerAfterFirst);
      expect(await movementCount(), movementsAfterFirst);
      expect(await openingLogCount(), logsAfterFirst);
      expect(await productStock(productId), stockA);
      expect(await productStock(productId2), stockB);
      expect(first.sealedProductIds, isNotEmpty);
      expect(second.sealedProductIds, isEmpty);
    });

    test('3) same key + different fingerprint conflict', () async {
      final key = b20OpeningStockSaveIdempotencyKey();
      await saveOpening(idempotencyKey: key, products: defaultProducts(qty: 50));

      await expectLater(
        saveOpening(idempotencyKey: key, products: defaultProducts(qty: 60)),
        throwsA(isA<OpeningStockSaveIdempotencyConflictException>()),
      );

      expect(await sealCount(), 2);
      expect(await openingLedgerCount(), 2);
    });

    test('4) sequential double submit same key', () async {
      final key = b20OpeningStockSaveIdempotencyKey();
      final fp = fingerprintFor();
      await saveOpening(idempotencyKey: key, fingerprint: fp);
      await saveOpening(idempotencyKey: key, fingerprint: fp);
      expect(await sealCount(), 2);
      expect(await bulkIdempotencyCount(), 1);
    });

    test('5) concurrent same key + same fingerprint', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b20_same_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 15000');
      rawB.execute('PRAGMA busy_timeout = 15000');
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

      final uid = await dbA.into(dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Conc User',
              username: 'conc_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Conc Product'),
              currentStock: Value(0),
              costPrice: Value(2),
              sellPrice: Value(5),
            ),
          );

      final serviceA = OpeningStockSaveService(dbA);
      final serviceB = OpeningStockSaveService(dbB);
      final sameKey = b20OpeningStockSaveIdempotencyKey();
      final products = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 20, unitCost: 2),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final outcomes = await Future.wait([
        serviceA.processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          products: products,
          createdBy: uid,
        ),
        serviceB.processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          products: products,
          createdBy: uid,
        ),
      ]);

      expect(await sealCount(dbA), 1);
      expect(await bulkIdempotencyCount(dbA), 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
    });

    test('6) concurrent same key + different fingerprint conflict', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b20_conflict_${DateTime.now().microsecondsSinceEpoch}.db';
      final rawA = sqlite3.sqlite3.open(dbPath);
      final rawB = sqlite3.sqlite3.open(dbPath);
      rawA.execute('PRAGMA busy_timeout = 15000');
      rawB.execute('PRAGMA busy_timeout = 15000');
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

      final uid = await dbA.into(dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Conflict User',
              username: 'conf_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Conflict Product'),
              currentStock: Value(0),
              costPrice: Value(2),
              sellPrice: Value(5),
            ),
          );

      final serviceA = OpeningStockSaveService(dbA);
      final serviceB = OpeningStockSaveService(dbB);
      final sameKey = b20OpeningStockSaveIdempotencyKey();
      final productsA = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 20, unitCost: 2),
      ];
      final productsB = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 25, unitCost: 2),
      ];
      final fpA = OpeningStockSaveFingerprint.compute(products: productsA, createdBy: uid);
      final fpB = OpeningStockSaveFingerprint.compute(products: productsB, createdBy: uid);

      final results = await Future.wait<Object?>([
        captureSaveOutcome(serviceA.processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fpA,
          products: productsA,
          createdBy: uid,
        )),
        captureSaveOutcome(serviceB.processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fpB,
          products: productsB,
          createdBy: uid,
        )),
      ]);

      final errors = results.whereType<OpeningStockSaveIdempotencyConflictException>();
      expect(errors.length, 1);
      expect(await sealCount(dbA), 1);
    });

    test('7) different keys same products', () async {
      await saveOpening(idempotencyKey: b20OpeningStockSaveIdempotencyKey());
      await expectLater(
        saveOpening(idempotencyKey: b20OpeningStockSaveIdempotencyKey()),
        throwsA(isA<OpeningStockProductAlreadyOpenedException>()),
      );
      expect(await bulkIdempotencyCount(), 1);
    });

    test('8) save after sale rejected', () async {
      final soldPid = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Sold Product'),
              currentStock: Value(10),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
      await recordSale(soldPid);

      await expectLater(
        saveOpening(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          products: [
            OpeningStockFingerprintProduct(
              productId: soldPid,
              quantity: 50,
              unitCost: 5,
            ),
          ],
        ),
        throwsA(isA<OpeningStockLiveActivityException>()),
      );
      expect(await sealCount(), 0);
    });

    test('9) save after purchase rejected', () async {
      final purchasedPid = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Purchased Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
      await recordPurchase(purchasedPid);

      await expectLater(
        saveOpening(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          products: [
            OpeningStockFingerprintProduct(
              productId: purchasedPid,
              quantity: 50,
              unitCost: 5,
            ),
          ],
        ),
        throwsA(isA<OpeningStockLiveActivityException>()),
      );
      expect(await sealCount(), 0);
    });

    test('10) save after adjustment rejected', () async {
      final adjustedPid = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Adjusted Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
      await recordAdjustment(adjustedPid);

      await expectLater(
        saveOpening(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          products: [
            OpeningStockFingerprintProduct(
              productId: adjustedPid,
              quantity: 50,
              unitCost: 5,
            ),
          ],
        ),
        throwsA(isA<OpeningStockLiveActivityException>()),
      );
      expect(await sealCount(), 0);
    });

    test('11) correction via adjustment remains allowed', () async {
      final key = b20OpeningStockSaveIdempotencyKey();
      await saveOpening(
        idempotencyKey: key,
        products: [
          OpeningStockFingerprintProduct(
            productId: productId,
            quantity: 40,
            unitCost: 5,
          ),
        ],
      );
      expect(await productStock(productId), 40);

      await db.stockDao.createAdjustment(
        productId: productId,
        quantityChange: -5,
        adjustmentType: 'decrease',
        reason: 'B20 correction',
        createdByUserId: userId,
      );
      expect(await productStock(productId), 35);
    });

    test('12) multi-product rollback on first violating product', () async {
      await saveOpening(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        products: [
          OpeningStockFingerprintProduct(
            productId: productId,
            quantity: 10,
            unitCost: 5,
          ),
        ],
      );

      await expectLater(
        saveOpening(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          products: defaultProducts(),
        ),
        throwsA(isA<OpeningStockProductAlreadyOpenedException>()),
      );

      expect(await sealCount(), 1);
      expect(await openingLedgerCount(null, productId2), 0);
      expect(await productStock(productId2), 0);
    });

    test('13) duplicate productId rejected before mutation', () async {
      final dupProducts = [
        OpeningStockFingerprintProduct(productId: productId, quantity: 10, unitCost: 5),
        OpeningStockFingerprintProduct(productId: productId, quantity: 20, unitCost: 5),
      ];
      await expectLater(
        service.processSave(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          fingerprintHash: 'unused',
          products: dupProducts,
          createdBy: userId,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await sealCount(), 0);
    });

    test('13b) createdBy <= 0 rejected with zero mutation', () async {
      await expectLater(
        service.processSave(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          fingerprintHash: fingerprintFor(),
          products: defaultProducts(),
          createdBy: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await sealCount(), 0);
      expect(await bulkIdempotencyCount(), 0);
      expect(await openingLedgerCount(), 0);
      expect(await movementCount(), 0);
      expect(await openingLogCount(), 0);
      expect(await productStock(productId), 0);
    });

    test('14a) opening-first vs sale — exact stock ordering', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Sale Opening First User',
              username: 'sof_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Sale Opening First Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      const openingQty = 100.0;
      const saleQty = 1.0;
      final inventoryMayStart = Completer<void>();
      final releaseOpening = Completer<void>();
      final saleInvokeStarted = Completer<void>();
      final saleInvokeFinished = Completer<void>();

      final openingService = OpeningStockSaveService(
        opened.dbA,
        afterEligibilityCheckHook: () async {
          inventoryMayStart.complete();
          await releaseOpening.future;
        },
      );
      final products = [
        OpeningStockFingerprintProduct(
          productId: pid,
          quantity: openingQty,
          unitCost: 5,
        ),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);
      final key = b20OpeningStockSaveIdempotencyKey();

      final openingFuture = openingService.processSave(
        idempotencyKey: key,
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      );

      await inventoryMayStart.future;

      final saleFuture = () async {
        saleInvokeStarted.complete();
        try {
          await recordSale(pid, qty: saleQty, database: opened.dbB);
        } finally {
          if (!saleInvokeFinished.isCompleted) {
            saleInvokeFinished.complete();
          }
        }
      }();

      await saleInvokeStarted.future;
      expect(saleInvokeFinished.isCompleted, isFalse,
          reason: 'sale must not complete while opening holds IMMEDIATE lock');
      expect(await liveLedgerCount(opened.dbA, pid), 0);
      expect(await productStock(pid, opened.dbA), 0);

      releaseOpening.complete();
      final openingResult = await openingFuture;
      await saleFuture;

      expect(openingResult.idempotentReplay, isFalse);
      expect(await sealCount(opened.dbA), 1);
      expect(await openingLedgerCount(opened.dbA, pid), 1);
      expect(await liveLedgerCount(opened.dbA, pid), 1);
      expect(await bulkIdempotencyCount(opened.dbA), 1);
      expect(await openingLogCount(opened.dbA), 1);
      expect(await movementCount(opened.dbA, pid), 1);
      expect(await productStock(pid, opened.dbA), openingQty - saleQty);
    });

    test('14b) sale-first vs opening — zero opening mutation', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Sale Inventory First User',
              username: 'sif_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Sale Inventory First Product'),
              currentStock: Value(10),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      await recordSale(pid, qty: 1, database: opened.dbB);
      expect(await productStock(pid, opened.dbA), 9);

      final openingService = OpeningStockSaveService(opened.dbA);
      final products = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 100, unitCost: 5),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final outcome = await captureSaveOutcome(openingService.processSave(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      ));

      expect(outcome, isA<OpeningStockLiveActivityException>());
      await expectZeroOpeningState(database: opened.dbA, productId: pid);
      expect(await liveLedgerCount(opened.dbA, pid), 1);
      expect(await productStock(pid, opened.dbA), 9);
    });

    test('15a) opening-first vs purchase — exact stock ordering', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Purchase Opening First User',
              username: 'pof_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final sid = await opened.dbA.into(opened.dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Purchase Opening Supplier')),
          );
      supplierId = sid;
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Purchase Opening First Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      const openingQty = 100.0;
      const purchaseQty = 10.0;
      final inventoryMayStart = Completer<void>();
      final releaseOpening = Completer<void>();
      final purchaseInvokeStarted = Completer<void>();
      final purchaseInvokeFinished = Completer<void>();

      final openingService = OpeningStockSaveService(
        opened.dbA,
        afterEligibilityCheckHook: () async {
          inventoryMayStart.complete();
          await releaseOpening.future;
        },
      );
      final products = [
        OpeningStockFingerprintProduct(
          productId: pid,
          quantity: openingQty,
          unitCost: 5,
        ),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final openingFuture = openingService.processSave(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      );

      await inventoryMayStart.future;

      final purchaseFuture = () async {
        purchaseInvokeStarted.complete();
        try {
          await recordPurchase(pid, database: opened.dbB);
        } finally {
          if (!purchaseInvokeFinished.isCompleted) {
            purchaseInvokeFinished.complete();
          }
        }
      }();

      await purchaseInvokeStarted.future;
      expect(purchaseInvokeFinished.isCompleted, isFalse);
      expect(await liveLedgerCount(opened.dbA, pid), 0);
      expect(await productStock(pid, opened.dbA), 0);

      releaseOpening.complete();
      await openingFuture;
      await purchaseFuture;

      expect(await sealCount(opened.dbA), 1);
      expect(await openingLedgerCount(opened.dbA, pid), 1);
      expect(await liveLedgerCount(opened.dbA, pid), 1);
      expect(await bulkIdempotencyCount(opened.dbA), 1);
      expect(await openingLogCount(opened.dbA), 1);
      expect(await productStock(pid, opened.dbA), openingQty + purchaseQty);
    });

    test('15b) purchase-first vs opening — zero opening mutation', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Purchase Inventory First User',
              username: 'pif_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final sid = await opened.dbA.into(opened.dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Purchase Inventory Supplier')),
          );
      supplierId = sid;
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Purchase Inventory First Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      await recordPurchase(pid, database: opened.dbB);
      expect(await productStock(pid, opened.dbA), 10);

      final openingService = OpeningStockSaveService(opened.dbA);
      final products = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 100, unitCost: 5),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final outcome = await captureSaveOutcome(openingService.processSave(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      ));

      expect(outcome, isA<OpeningStockLiveActivityException>());
      await expectZeroOpeningState(database: opened.dbA, productId: pid);
      expect(await liveLedgerCount(opened.dbA, pid), 1);
      expect(await productStock(pid, opened.dbA), 10);
    });

    test('16a) opening-first vs adjustment — exact stock ordering', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Adj Opening First User',
              username: 'aof_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Adj Opening First Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      const openingQty = 100.0;
      const adjustmentQty = 5.0;
      final openingAtBarrier = Completer<void>();
      final releaseOpening = Completer<void>();

      final openingService = OpeningStockSaveService(
        opened.dbA,
        afterEligibilityCheckHook: () async {
          openingAtBarrier.complete();
          await releaseOpening.future;
        },
      );
      final products = [
        OpeningStockFingerprintProduct(
          productId: pid,
          quantity: openingQty,
          unitCost: 5,
        ),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final openingFuture = openingService.processSave(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      );

      await openingAtBarrier.future;
      expect(await liveLedgerCount(opened.dbA, pid), 0);
      expect(await productStock(pid, opened.dbA), 0);
      expect(await sealCount(opened.dbA), 0);

      releaseOpening.complete();
      await openingFuture;

      expect(await productStock(pid, opened.dbA), openingQty);
      await recordAdjustment(
        pid,
        database: opened.dbB,
        createdByUserId: uid,
      );

      expect(await sealCount(opened.dbA), 1);
      expect(await openingLedgerCount(opened.dbA, pid), 1);
      expect(await liveLedgerCount(opened.dbA, pid), 1);
      expect(await bulkIdempotencyCount(opened.dbA), 1);
      expect(await openingLogCount(opened.dbA), 1);
      expect(await productStock(pid, opened.dbA), openingQty + adjustmentQty);
    });

    test('16b) adjustment-first vs opening — zero opening mutation', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Adj Inventory First User',
              username: 'aif_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Adj Inventory First Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      await recordAdjustment(
        pid,
        database: opened.dbB,
        createdByUserId: uid,
      );
      expect(await productStock(pid, opened.dbA), 5);

      final openingService = OpeningStockSaveService(opened.dbA);
      final products = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 100, unitCost: 5),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final outcome = await captureSaveOutcome(openingService.processSave(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      ));

      expect(outcome, isA<OpeningStockLiveActivityException>());
      await expectZeroOpeningState(database: opened.dbA, productId: pid);
      expect(await liveLedgerCount(opened.dbA, pid), 1);
      expect(await productStock(pid, opened.dbA), 5);
    });

    test('17) current_stock consistency after first opening', () async {
      await saveOpening(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        products: [
          OpeningStockFingerprintProduct(
            productId: productId,
            quantity: 77.5,
            unitCost: 4.25,
          ),
        ],
      );
      expect(await productStock(productId), 77.5);
    });

    test('18) single OPENING ledger per product without DELETE pattern', () async {
      final key = b20OpeningStockSaveIdempotencyKey();
      await saveOpening(
        idempotencyKey: key,
        products: [
          OpeningStockFingerprintProduct(
            productId: productId,
            quantity: 10,
            unitCost: 5,
          ),
        ],
      );
      expect(await openingLedgerCount(null, productId), 1);

      await expectLater(
        saveOpening(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          products: [
            OpeningStockFingerprintProduct(
              productId: productId,
              quantity: 20,
              unitCost: 5,
            ),
          ],
        ),
        throwsA(isA<OpeningStockProductAlreadyOpenedException>()),
      );
      expect(await openingLedgerCount(null, productId), 1);
    });

    test('19) migration v46 -> v47 creates opening stock protection tables', () async {
      final opened = await openSimulatedV46RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='product_opening_stock_seals'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 47);
      final tables = await migrated.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('opening_stock_idempotency','product_opening_stock_seals')",
      ).get();
      expect(tables.length, 2);
    });

    test('20) transactional log rollback on failure after product writes', () async {
      final flaky = OpeningStockSaveService(
        db,
        beforeLogInsertHook: () async {
          throw StateError('forced log failure');
        },
      );

      await expectLater(
        saveOpening(
          targetService: flaky,
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await sealCount(), 0);
      expect(await bulkIdempotencyCount(), 0);
      expect(await openingLedgerCount(), 0);
      expect(await openingLogCount(), 0);
      expect(await productStock(productId), 0);
    });

    test('20b) bulk idempotency seal failure rolls back complete opening state', () async {
      final flaky = OpeningStockSaveService(
        db,
        preSealHook: () async {
          throw StateError('forced bulk seal failure');
        },
      );
      final key = b20OpeningStockSaveIdempotencyKey();
      final fp = fingerprintFor();

      await expectLater(
        saveOpening(
          targetService: flaky,
          idempotencyKey: key,
          fingerprint: fp,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await sealCount(), 0);
      expect(await bulkIdempotencyCount(), 0);
      expect(await openingLedgerCount(), 0);
      expect(await movementCount(), 0);
      expect(await openingLogCount(), 0);
      expect(await productStock(productId), 0);
      expect(await productStock(productId2), 0);

      final retry = await saveOpening(
        idempotencyKey: key,
        fingerprint: fp,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await sealCount(), 2);
      expect(await bulkIdempotencyCount(), 1);
    });

    test('20c) real bulk idempotency PK constraint and processSave replay', () async {
      final key = b20OpeningStockSaveIdempotencyKey();
      final fp = fingerprintFor();

      await db.openingStockIdempotencyDao.insertCompletedRecord(
        idempotencyKey: key,
        fingerprintHash: fp,
      );

      await expectLater(
        db.openingStockIdempotencyDao.insertCompletedRecord(
          idempotencyKey: key,
          fingerprintHash: fp,
        ),
        throwsA(
          predicate<SqliteException>(
            (e) =>
                e.extendedResultCode == 1555 ||
                e.extendedResultCode == 2067,
          ),
        ),
      );

      final result = await saveOpening(idempotencyKey: key, fingerprint: fp);

      expect(result.idempotentReplay, isTrue);
      expect(result.sealedProductIds, isEmpty);
      expect(await bulkIdempotencyCount(), 1);
      expect(await sealCount(), 0);
      expect(await openingLedgerCount(), 0);
      expect(await movementCount(), 0);
      expect(await openingLogCount(), 0);
    });

    test('20d) concurrent same-key bulk seal produces one record and replay', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Bulk Seal Race User',
              username: 'bsr_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('Bulk Seal Race Product'),
              currentStock: Value(0),
              costPrice: Value(2),
              sellPrice: Value(5),
            ),
          );

      final releaseWinner = Completer<void>();
      final serviceA = OpeningStockSaveService(
        opened.dbA,
        preSealHook: () async => releaseWinner.future,
      );
      final serviceB = OpeningStockSaveService(opened.dbB);
      final sameKey = b20OpeningStockSaveIdempotencyKey();
      final products = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 20, unitCost: 2),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final futureA = serviceA.processSave(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      );
      final futureB = serviceB.processSave(
        idempotencyKey: sameKey,
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      );

      releaseWinner.complete();
      final outcomes = await Future.wait([
        futureA,
        futureB,
      ]);

      expect(await bulkIdempotencyCount(opened.dbA), 1);
      expect(await sealCount(opened.dbA), 1);
      expect(await openingLedgerCount(opened.dbA, pid), 1);
      expect(await movementCount(opened.dbA, pid), 1);
      expect(await openingLogCount(opened.dbA), 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('21) deterministic TOCTOU: IMMEDIATE txn blocks concurrent sale', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'TOCTOU User',
              username: 'toctou_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final pid = await opened.dbA.into(opened.dbA.products).insert(
            const ProductsCompanion(
              name: Value('TOCTOU Product'),
              currentStock: Value(0),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      final saleMayStart = Completer<void>();
      final releaseOpening = Completer<void>();
      final saleInvokeStarted = Completer<void>();
      final saleInvokeFinished = Completer<void>();

      final openingService = OpeningStockSaveService(
        opened.dbA,
        afterEligibilityCheckHook: () async {
          saleMayStart.complete();
          await releaseOpening.future;
        },
      );
      final products = [
        OpeningStockFingerprintProduct(productId: pid, quantity: 100, unitCost: 5),
      ];
      final fp = OpeningStockSaveFingerprint.compute(products: products, createdBy: uid);

      final openingFuture = openingService.processSave(
        idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        fingerprintHash: fp,
        products: products,
        createdBy: uid,
      );

      await saleMayStart.future;

      final saleFuture = () async {
        saleInvokeStarted.complete();
        try {
          await recordSale(pid, qty: 1, database: opened.dbB);
        } finally {
          if (!saleInvokeFinished.isCompleted) {
            saleInvokeFinished.complete();
          }
        }
      }();

      await saleInvokeStarted.future;
      expect(saleInvokeFinished.isCompleted, isFalse,
          reason: 'sale must not complete while opening holds IMMEDIATE lock');
      expect(await liveLedgerCount(opened.dbA, pid), 0);
      expect(await productStock(pid, opened.dbA), 0);

      releaseOpening.complete();
      final openingResult = await openingFuture;
      await saleFuture;

      expect(openingResult.idempotentReplay, isFalse);
      expect(await sealCount(opened.dbA), 1);
      expect(await openingLedgerCount(opened.dbA, pid), 1);
      expect(await bulkIdempotencyCount(opened.dbA), 1);
      expect(await openingLogCount(opened.dbA), 1);
      expect(await liveLedgerCount(opened.dbA, pid), 1);
      expect(await productStock(pid, opened.dbA), 99);
    });

    test('22) concurrent overlapping bulk A=[p1,p2] vs B=[p2,p3]', () async {
      final opened = await openDualConnectionRaceDatabases();
      addTearDown(() async {
        await opened.dbA.close();
        await opened.dbB.close();
        disposeDualConnectionRaceDatabases(opened);
      });

      final uid = await opened.dbA.into(opened.dbA.usersTable).insert(
            UsersTableCompanion.insert(
              fullName: 'Overlap Bulk User',
              username: 'ob_${DateTime.now().microsecondsSinceEpoch}',
              passwordHash: 'hash',
              roleId: 1,
            ),
          );
      final label = DateTime.now().microsecondsSinceEpoch;
      final p1 = await opened.dbA.into(opened.dbA.products).insert(
            ProductsCompanion(
              name: Value('Overlap P1 $label'),
              barcode: Value('OB-P1-$label'),
              currentStock: const Value(0),
              costPrice: const Value(2),
              sellPrice: const Value(5),
            ),
          );
      final p2 = await opened.dbA.into(opened.dbA.products).insert(
            ProductsCompanion(
              name: Value('Overlap P2 $label'),
              barcode: Value('OB-P2-$label'),
              currentStock: const Value(0),
              costPrice: const Value(2),
              sellPrice: const Value(5),
            ),
          );
      final p3 = await opened.dbA.into(opened.dbA.products).insert(
            ProductsCompanion(
              name: Value('Overlap P3 $label'),
              barcode: Value('OB-P3-$label'),
              currentStock: const Value(0),
              costPrice: const Value(2),
              sellPrice: const Value(5),
            ),
          );

      final serviceA = OpeningStockSaveService(opened.dbA);
      final serviceB = OpeningStockSaveService(opened.dbB);
      final productsA = [
        OpeningStockFingerprintProduct(productId: p1, quantity: 10, unitCost: 2),
        OpeningStockFingerprintProduct(productId: p2, quantity: 20, unitCost: 2),
      ];
      final productsB = [
        OpeningStockFingerprintProduct(productId: p2, quantity: 30, unitCost: 2),
        OpeningStockFingerprintProduct(productId: p3, quantity: 40, unitCost: 2),
      ];
      final fpA = OpeningStockSaveFingerprint.compute(
        products: productsA,
        createdBy: uid,
      );
      final fpB = OpeningStockSaveFingerprint.compute(
        products: productsB,
        createdBy: uid,
      );

      final results = await Future.wait<Object?>([
        captureSaveOutcome(serviceA.processSave(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          fingerprintHash: fpA,
          products: productsA,
          createdBy: uid,
        )),
        captureSaveOutcome(serviceB.processSave(
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
          fingerprintHash: fpB,
          products: productsB,
          createdBy: uid,
        )),
      ]);
      final resultA = results[0];
      final resultB = results[1];

      final aSucceeded = resultA is OpeningStockSaveResult;
      final bSucceeded = resultB is OpeningStockSaveResult;
      expect(aSucceeded ^ bSucceeded, isTrue,
          reason: 'exactly one overlapping bulk save must succeed');

      final p2Seal = await (opened.dbA.select(opened.dbA.productOpeningStockSeals)
            ..where((s) => s.productId.equals(p2)))
          .getSingleOrNull();
      expect(p2Seal, isNotNull);
      expect(await bulkIdempotencyCount(opened.dbA), 1);
      expect(await openingLogCount(opened.dbA), 1);

      if (aSucceeded) {
        expect(resultB, isA<OpeningStockProductAlreadyOpenedException>());
        expect(await openingLedgerCount(opened.dbA, p1), 1);
        expect(await openingLedgerCount(opened.dbA, p2), 1);
        expect(await openingLedgerCount(opened.dbA, p3), 0);
        expect(await productStock(p1, opened.dbA), 10);
        expect(await productStock(p2, opened.dbA), 20);
        expect(await productStock(p3, opened.dbA), 0);
      } else {
        expect(resultA, isA<OpeningStockProductAlreadyOpenedException>());
        expect(await openingLedgerCount(opened.dbA, p1), 0);
        expect(await openingLedgerCount(opened.dbA, p2), 1);
        expect(await openingLedgerCount(opened.dbA, p3), 1);
        expect(await productStock(p1, opened.dbA), 0);
        expect(await productStock(p2, opened.dbA), 30);
        expect(await productStock(p3, opened.dbA), 40);
      }
    });

    test('23) unrelated NOT NULL constraint is not treated as seal race', () async {
      final flaky = OpeningStockSaveService(
        db,
        beforeLogInsertHook: () async {
          throw SqliteException(
            1299,
            'NOT NULL constraint failed: logs_table.user_id',
          );
        },
      );

      await expectLater(
        saveOpening(
          targetService: flaky,
          idempotencyKey: b20OpeningStockSaveIdempotencyKey(),
        ),
        throwsA(isA<SqliteException>()),
      );

      expect(await sealCount(), 0);
      expect(await bulkIdempotencyCount(), 0);
      expect(await openingLedgerCount(), 0);
      expect(await movementCount(), 0);
      expect(await openingLogCount(), 0);
    });
  });

  group('B20 v46->v47 legacy migration cases', () {
    int insertLegacyProduct(sqlite3.Database rawDb, String label) {
      rawDb.execute(
        "INSERT INTO products (name, current_stock, cost_price, sell_price, is_active) VALUES (?, 42, 5, 10, 1)",
        ['Legacy $label'],
      );
      return rawDb.lastInsertRowId;
    }

    void insertOpeningLedgerRaw(
      sqlite3.Database rawDb,
      int pid, {
      required double qty,
      required double cost,
    }) {
      rawDb.execute(
        "INSERT INTO stock_ledger (product_id, movement_type, quantity_change, unit_cost, reference_type) VALUES (?, 'OPENING', ?, ?, 'opening')",
        [pid, qty, cost],
      );
    }

    void insertLiveLedgerRaw(
      sqlite3.Database rawDb,
      int pid,
      String movementType, {
      double qty = 1,
    }) {
      rawDb.execute(
        'INSERT INTO stock_ledger (product_id, movement_type, quantity_change, reference_type) VALUES (?, ?, ?, ?)',
        [pid, movementType, qty, 'test'],
      );
    }

    Future<void> runMigrationCase({
      required String label,
      required void Function(sqlite3.Database rawDb, int pid) arrange,
      required Future<void> Function(
        AppDatabase migrated,
        int pid,
        double stockBefore,
        int ledgerBefore,
        int movementsBefore,
      ) verify,
    }) async {
      final opened = await openSimulatedV46RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final pid = insertLegacyProduct(opened.rawDb, label);
      arrange(opened.rawDb, pid);

      final stockBefore = (opened.rawDb
              .select('SELECT current_stock FROM products WHERE id = ?', [pid])
              .first['current_stock'] as num)
          .toDouble();
      final ledgerBefore = opened.rawDb
          .select('SELECT COUNT(*) AS cnt FROM stock_ledger')
          .first['cnt'] as int;
      final movementsBefore = opened.rawDb
          .select('SELECT COUNT(*) AS cnt FROM stock_movements')
          .first['cnt'] as int;

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      await verify(migrated, pid, stockBefore, ledgerBefore, movementsBefore);
    }

    test('A) OPENING only backfills seal', () async {
      await runMigrationCase(
        label: 'A',
        arrange: (rawDb, pid) {
          insertOpeningLedgerRaw(rawDb, pid, qty: 15, cost: 3);
        },
        verify: (migrated, pid, stockBefore, ledgerBefore, movementsBefore) async {
          final seal = await (migrated.select(migrated.productOpeningStockSeals)
                ..where((s) => s.productId.equals(pid)))
              .getSingleOrNull();
          expect(seal, isNotNull);
          expect(seal!.quantity, 15);
          expect(seal.unitCost, 3);
          expect(seal.idempotencyKey, OpeningStockSaveFingerprint.legacyBackfillKey);
          expect(seal.createdBy, OpeningStockSaveFingerprint.legacySystemCreatedBy);
          expect(await productStock(pid, migrated), stockBefore);
          expect(
            (await migrated.customSelect('SELECT COUNT(*) AS cnt FROM stock_ledger').getSingle())
                .data['cnt'],
            ledgerBefore,
          );
          expect(
            (await migrated.customSelect('SELECT COUNT(*) AS cnt FROM stock_movements').getSingle())
                .data['cnt'],
            movementsBefore,
          );
        },
      );
    });

    test('B) OPENING + SALE backfills seal without mutating stock', () async {
      await runMigrationCase(
        label: 'B',
        arrange: (rawDb, pid) {
          insertOpeningLedgerRaw(rawDb, pid, qty: 10, cost: 2);
          insertLiveLedgerRaw(rawDb, pid, StockMovementType.sale.code, qty: -1);
        },
        verify: (migrated, pid, stockBefore, ledgerBefore, movementsBefore) async {
          expect(await (migrated.select(migrated.productOpeningStockSeals)
                ..where((s) => s.productId.equals(pid)))
              .getSingleOrNull(), isNotNull);
          expect(await productStock(pid, migrated), stockBefore);
          expect(
            (await migrated.customSelect('SELECT COUNT(*) AS cnt FROM stock_ledger').getSingle())
                .data['cnt'],
            ledgerBefore,
          );
        },
      );
    });

    test('C) OPENING + PURCHASE backfills seal', () async {
      await runMigrationCase(
        label: 'C',
        arrange: (rawDb, pid) {
          insertOpeningLedgerRaw(rawDb, pid, qty: 10, cost: 2);
          insertLiveLedgerRaw(rawDb, pid, StockMovementType.purchase.code, qty: 5);
        },
        verify: (migrated, pid, stockBefore, ledgerBefore, movementsBefore) async {
          expect(await (migrated.select(migrated.productOpeningStockSeals)
                ..where((s) => s.productId.equals(pid)))
              .getSingleOrNull(), isNotNull);
          expect(await productStock(pid, migrated), stockBefore);
        },
      );
    });

    test('D) OPENING + ADJUSTMENT backfills seal', () async {
      await runMigrationCase(
        label: 'D',
        arrange: (rawDb, pid) {
          insertOpeningLedgerRaw(rawDb, pid, qty: 10, cost: 2);
          insertLiveLedgerRaw(rawDb, pid, StockMovementType.adjustment.code, qty: 2);
        },
        verify: (migrated, pid, stockBefore, ledgerBefore, movementsBefore) async {
          expect(await (migrated.select(migrated.productOpeningStockSeals)
                ..where((s) => s.productId.equals(pid)))
              .getSingleOrNull(), isNotNull);
          expect(await productStock(pid, migrated), stockBefore);
        },
      );
    });

    test('E) multiple OPENING rows uses latest by MAX(id)', () async {
      await runMigrationCase(
        label: 'E',
        arrange: (rawDb, pid) {
          insertOpeningLedgerRaw(rawDb, pid, qty: 5, cost: 1);
          insertOpeningLedgerRaw(rawDb, pid, qty: 99, cost: 9);
        },
        verify: (migrated, pid, stockBefore, ledgerBefore, movementsBefore) async {
          final seal = await (migrated.select(migrated.productOpeningStockSeals)
                ..where((s) => s.productId.equals(pid)))
              .getSingle();
          expect(seal.quantity, 99);
          expect(seal.unitCost, 9);
        },
      );
    });

    test('F) no OPENING row receives no seal', () async {
      await runMigrationCase(
        label: 'F',
        arrange: (rawDb, pid) {},
        verify: (migrated, pid, stockBefore, ledgerBefore, movementsBefore) async {
          expect(await (migrated.select(migrated.productOpeningStockSeals)
                ..where((s) => s.productId.equals(pid)))
              .getSingleOrNull(), isNull);
          expect(await productStock(pid, migrated), stockBefore);
        },
      );
    });
  });
}