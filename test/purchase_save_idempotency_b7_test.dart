import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/credit_limit_exception.dart';
import 'package:lez_pos/core/services/customer_account_service.dart';
import 'package:lez_pos/core/services/pos_sale_fingerprint.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/purchase_fingerprint.dart';
import 'package:lez_pos/core/services/purchase_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/purchase_save_result.dart';
import 'package:lez_pos/core/services/purchase_save_service.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_payment_exceeds_payable_exception.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/pos/models/cart_item.dart';
import 'package:lez_pos/features/products/models/product_model.dart';
import 'package:lez_pos/features/products/providers/products_provider.dart';
import 'package:lez_pos/features/products/repositories/products_repository.dart';
import 'package:lez_pos/features/auth/providers/auth_provider.dart';
import 'package:lez_pos/features/purchases/models/purchase_invoice_model.dart';
import 'package:lez_pos/features/purchases/providers/purchases_provider.dart';
import 'package:lez_pos/features/purchases/repositories/purchases_repository.dart';
import 'package:lez_pos/features/purchases/screens/purchase_form_screen.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/suppliers/models/supplier_model.dart';
import 'package:lez_pos/features/suppliers/providers/supplier_accounts_provider.dart';
import 'package:lez_pos/features/suppliers/providers/suppliers_provider.dart';
import 'package:lez_pos/features/suppliers/repositories/suppliers_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uuid/uuid.dart';

import 'support/customer_payment_test_keys.dart';
import 'support/purchase_save_test_keys.dart';

const _b7RegressionUuid = Uuid();
String _b7RegressionPosSaleKey() => _b7RegressionUuid.v4();
const _b7RegressionCreditFingerprint = 'b7-b2-b6-regression-credit-fingerprint';

class _TestAuthNotifier extends AuthNotifier {
  @override
  FutureOr<AuthState> build() async => const AuthState();
}

class _TestPurchasesNotifier extends PurchasesNotifier {
  @override
  Future<List<PurchaseInvoiceModel>> build() async => const [];
}

class _TestProductsNotifier extends ProductsNotifier {
  @override
  Future<List<ProductModel>> build() async => const [];
}

class _CountingPurchaseSaveService extends PurchaseSaveService {
  _CountingPurchaseSaveService(
    super.db, {
    Completer<void>? saveGate,
    this.stubResponse = false,
  }) : _saveGate = saveGate;

  final Completer<void>? _saveGate;
  final bool stubResponse;
  int processSaveCalls = 0;

  @override
  Future<PurchaseSaveResult> processSave({
    required String idempotencyKey,
    required String fingerprintHash,
    required int? supplierId,
    required String operatorInvoiceNumber,
    required DateTime purchaseDate,
    required double invoiceDiscount,
    required double total,
    required double paidAmount,
    required DateTime? dueDate,
    required String notes,
    required List<Map<String, dynamic>> items,
    int? createdByUserId,
  }) async {
    processSaveCalls++;
    final gate = _saveGate;
    if (gate != null) {
      await gate.future;
    }
    if (stubResponse) {
      return const PurchaseSaveResult(
        purchaseInvoiceId: 1,
        purchaseInvoiceNumber: 'UI-TEST-PUR-1',
        idempotentReplay: false,
      );
    }
    return super.processSave(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      supplierId: supplierId,
      operatorInvoiceNumber: operatorInvoiceNumber,
      purchaseDate: purchaseDate,
      invoiceDiscount: invoiceDiscount,
      total: total,
      paidAmount: paidAmount,
      dueDate: dueDate,
      notes: notes,
      items: items,
      createdByUserId: createdByUserId,
    );
  }
}

Future<({sqlite3.Database rawDb, String path})>
    openSimulatedV38RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b7_v38_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement('DROP TABLE IF EXISTS purchase_idempotency');
  await bootstrap
      .customStatement('DROP INDEX IF EXISTS pi_purchase_invoice_idx');
  await bootstrap.customStatement('PRAGMA user_version = 38');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 38);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  late AppDatabase db;
  late PurchaseSaveService saveService;
  late int productId;
  late int supplierId;
  final purchaseDate = DateTime(2026, 10, 1);

  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  List<Map<String, dynamic>> defaultItems({double qty = 10, double cost = 10}) {
    return [
      {'productId': productId, 'qty': qty, 'cost': cost, 'discount': 0.0},
    ];
  }

  String fingerprintFor({
    int? sid,
    double total = 100,
    double paidAmount = 0,
    String? operatorInvoiceNumber,
    List<PurchaseFingerprintLine>? lines,
  }) {
    return PurchaseFingerprint.compute(
      supplierId: sid ?? supplierId,
      operatorInvoiceNumber: operatorInvoiceNumber,
      purchaseDate: purchaseDate,
      invoiceDiscount: 0,
      total: total,
      paidAmount: paidAmount,
      dueDate: null,
      notes: '',
      items: lines ??
          [
            PurchaseFingerprintLine(
              productId: productId,
              quantity: 10,
              unitCost: 10,
            ),
          ],
    );
  }

  Future<PurchaseSaveResult> savePurchase({
    String? key,
    String? fingerprint,
    int? sid,
    double total = 100,
    double paidAmount = 0,
    String operatorInvoiceNumber = '',
    List<Map<String, dynamic>>? items,
  }) {
    final idempotencyKey = key ?? b7PurchaseIdempotencyKey();
    final fp = fingerprint ??
        fingerprintFor(
          sid: sid,
          total: total,
          paidAmount: paidAmount,
          operatorInvoiceNumber:
              operatorInvoiceNumber.isEmpty ? null : operatorInvoiceNumber,
        );
    return saveService.processSave(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fp,
      supplierId: sid ?? supplierId,
      operatorInvoiceNumber: operatorInvoiceNumber,
      purchaseDate: purchaseDate,
      invoiceDiscount: 0,
      total: total,
      paidAmount: paidAmount,
      dueDate: null,
      notes: '',
      items: items ?? defaultItems(),
    );
  }

  Future<int> invoiceCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.purchaseInvoices).get()).length;
  }

  Future<double> productStock([AppDatabase? database]) async {
    final target = database ?? db;
    final row = await (target.select(target.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    return row.currentStock;
  }

  Future<int> supplierPurchaseTxnCount(
      [AppDatabase? database, int? sid]) async {
    final target = database ?? db;
    return (await (target.select(target.supplierTransactions)
              ..where((t) =>
                  t.supplierId.equals(sid ?? supplierId) &
                  t.type.equals('PURCHASE')))
            .get())
        .length;
  }

  Future<double> supplierBalance([AppDatabase? database, int? sid]) {
    final target = database ?? db;
    return target.supplierAccountsDao
        .calculateBalanceFromTransactions(sid ?? supplierId);
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.purchaseIdempotency).get()).length;
  }

  Future<int> purchaseCashLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    final ledger = FinancialLedgerRepository(target);
    return (await ledger.getEntries(ledgerFilter))
        .entries
        .where((e) => e.eventType == CashLedgerEventType.purchaseCash)
        .length;
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='purchase_idempotency'",
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<bool> idempotencyIndexExists(AppDatabase database) async {
    final rows = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name='pi_purchase_invoice_idx'",
        )
        .get();
    return rows.isNotEmpty;
  }

  group('B7 purchase save idempotency', () {
    setUp(() async {
      db = AppDatabase.test();
      saveService = PurchaseSaveService(db);
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('B7 Product'),
              barcode: Value('B7-PROD'),
              currentStock: Value(50),
              costPrice: Value(5),
            ),
          );
      supplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('B7 Supplier')),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('1) first purchase succeeds', () async {
      final result = await savePurchase();
      expect(result.idempotentReplay, isFalse);
      expect(result.purchaseInvoiceId, greaterThan(0));
      expect(result.purchaseInvoiceNumber, startsWith('PUR-'));
      expect(await invoiceCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('2) same key + same fingerprint replays', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor();
      final first = await savePurchase(key: key, fingerprint: fp);
      final second = await savePurchase(key: key, fingerprint: fp);
      expect(second.idempotentReplay, isTrue);
      expect(second.purchaseInvoiceId, first.purchaseInvoiceId);
    });

    test('3) replay returns original purchase ID', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor();
      final first = await savePurchase(key: key, fingerprint: fp);
      final second = await savePurchase(key: key, fingerprint: fp);
      expect(second.purchaseInvoiceId, first.purchaseInvoiceId);
      expect(await invoiceCount(), 1);
    });

    test('4) replay does not duplicate stock', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor();
      await savePurchase(key: key, fingerprint: fp);
      final stockAfterFirst = await productStock();
      await savePurchase(key: key, fingerprint: fp);
      expect(await productStock(), stockAfterFirst);
      expect(await invoiceCount(), 1);
    });

    test('5) replay does not duplicate supplier debt', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor(total: 100, paidAmount: 40);
      await savePurchase(
        key: key,
        fingerprint: fp,
        total: 100,
        paidAmount: 40,
      );
      final balanceAfterFirst = await supplierBalance();
      await savePurchase(
        key: key,
        fingerprint: fp,
        total: 100,
        paidAmount: 40,
      );
      expect(await supplierPurchaseTxnCount(), 1);
      expect(await supplierBalance(), balanceAfterFirst);
    });

    test('6) replay does not duplicate purchase cash ledger', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor(total: 100, paidAmount: 60);
      await savePurchase(
        key: key,
        fingerprint: fp,
        total: 100,
        paidAmount: 60,
      );
      await savePurchase(
        key: key,
        fingerprint: fp,
        total: 100,
        paidAmount: 60,
      );
      expect(await purchaseCashLedgerCount(), 1);
    });

    test('7) same key + changed total -> conflict', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor(total: 100);
      await savePurchase(key: key, fingerprint: fp, total: 100);
      await expectLater(
        savePurchase(
          key: key,
          fingerprint: fingerprintFor(total: 110),
          total: 110,
          items: defaultItems(qty: 11, cost: 10),
        ),
        throwsA(isA<PurchaseIdempotencyConflictException>()),
      );
      expect(await invoiceCount(), 1);
    });

    test('8) same key + changed supplier -> conflict', () async {
      final otherSupplier = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Other Supplier')),
          );
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor();
      await savePurchase(key: key, fingerprint: fp);
      await expectLater(
        savePurchase(
          key: key,
          fingerprint: fingerprintFor(sid: otherSupplier),
          sid: otherSupplier,
        ),
        throwsA(isA<PurchaseIdempotencyConflictException>()),
      );
      expect(await invoiceCount(), 1);
    });

    test('9) same key + changed line item -> conflict', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor();
      await savePurchase(key: key, fingerprint: fp);
      final otherProduct = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Other Product'),
              barcode: Value('B7-OTHER'),
              currentStock: Value(10),
            ),
          );
      await expectLater(
        saveService.processSave(
          idempotencyKey: key,
          fingerprintHash: fingerprintFor(
            lines: [
              PurchaseFingerprintLine(
                productId: otherProduct,
                quantity: 10,
                unitCost: 10,
              ),
            ],
          ),
          supplierId: supplierId,
          operatorInvoiceNumber: '',
          purchaseDate: purchaseDate,
          invoiceDiscount: 0,
          total: 100,
          paidAmount: 0,
          dueDate: null,
          notes: '',
          items: [
            {
              'productId': otherProduct,
              'qty': 10.0,
              'cost': 10.0,
              'discount': 0.0
            },
          ],
        ),
        throwsA(isA<PurchaseIdempotencyConflictException>()),
      );
      expect(await invoiceCount(), 1);
    });

    test('10) same key + changed payment split -> conflict', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor(total: 100, paidAmount: 0);
      await savePurchase(key: key, fingerprint: fp, total: 100, paidAmount: 0);
      await expectLater(
        savePurchase(
          key: key,
          fingerprint: fingerprintFor(total: 100, paidAmount: 50),
          total: 100,
          paidAmount: 50,
        ),
        throwsA(isA<PurchaseIdempotencyConflictException>()),
      );
      expect(await invoiceCount(), 1);
    });

    test('11) different keys create independent purchases', () async {
      await savePurchase(key: b7PurchaseIdempotencyKey());
      await savePurchase(key: b7PurchaseIdempotencyKey());
      expect(await invoiceCount(), 2);
      expect(await idempotencyRowCount(), 2);
    });

    test('12) dual-connection same-key concurrency', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b7_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Conc Product'),
              barcode: Value('B7-CONC'),
              currentStock: Value(20),
            ),
          );
      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Conc Supplier')),
          );

      final serviceA = PurchaseSaveService(dbA);
      final serviceB = PurchaseSaveService(dbB);
      final sameKey = b7PurchaseIdempotencyKey();
      final fp = PurchaseFingerprint.compute(
        supplierId: sid,
        operatorInvoiceNumber: null,
        purchaseDate: purchaseDate,
        invoiceDiscount: 0,
        total: 50,
        paidAmount: 0,
        dueDate: null,
        notes: '',
        items: [
          PurchaseFingerprintLine(productId: pid, quantity: 5, unitCost: 10),
        ],
      );
      final items = [
        {'productId': pid, 'qty': 5.0, 'cost': 10.0, 'discount': 0.0},
      ];

      final outcomes = await Future.wait([
        serviceA.processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          supplierId: sid,
          operatorInvoiceNumber: '',
          purchaseDate: purchaseDate,
          invoiceDiscount: 0,
          total: 50,
          paidAmount: 0,
          dueDate: null,
          notes: '',
          items: items,
        ),
        serviceB.processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          supplierId: sid,
          operatorInvoiceNumber: '',
          purchaseDate: purchaseDate,
          invoiceDiscount: 0,
          total: 50,
          paidAmount: 0,
          dueDate: null,
          notes: '',
          items: items,
        ),
      ]);

      expect(await invoiceCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.purchaseInvoiceId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('13) losing seal race rolls back purchase effects', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b7_seal_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Seal Product'),
              currentStock: Value(10),
            ),
          );
      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Seal Supplier')),
          );
      final sameKey = b7PurchaseIdempotencyKey();
      final fp = PurchaseFingerprint.compute(
        supplierId: sid,
        operatorInvoiceNumber: null,
        purchaseDate: purchaseDate,
        invoiceDiscount: 0,
        total: 30,
        paidAmount: 0,
        dueDate: null,
        notes: '',
        items: [
          PurchaseFingerprintLine(productId: pid, quantity: 3, unitCost: 10),
        ],
      );
      final items = [
        {'productId': pid, 'qty': 3.0, 'cost': 10.0, 'discount': 0.0},
      ];

      await Future.wait([
        PurchaseSaveService(dbA).processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          supplierId: sid,
          operatorInvoiceNumber: '',
          purchaseDate: purchaseDate,
          invoiceDiscount: 0,
          total: 30,
          paidAmount: 0,
          dueDate: null,
          notes: '',
          items: items,
        ),
        PurchaseSaveService(dbB).processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          supplierId: sid,
          operatorInvoiceNumber: '',
          purchaseDate: purchaseDate,
          invoiceDiscount: 0,
          total: 30,
          paidAmount: 0,
          dueDate: null,
          notes: '',
          items: items,
        ),
      ]);

      expect(await invoiceCount(dbA), 1);
      final row = await (dbA.select(dbA.products)
            ..where((p) => p.id.equals(pid)))
          .getSingle();
      expect(row.currentStock, 13);
      expect(await supplierPurchaseTxnCount(dbA, sid), 1);
    });

    test('14) preSealHook failure rolls back whole purchase', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor();
      final failingService = PurchaseSaveService(
        db,
        preSealHook: () async {
          throw Exception('forced seal failure');
        },
      );

      await expectLater(
        failingService.processSave(
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
          items: defaultItems(),
        ),
        throwsA(isA<Exception>()),
      );

      expect(await invoiceCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await productStock(), 50);

      final retry = await savePurchase(key: key, fingerprint: fp);
      expect(retry.idempotentReplay, isFalse);
      expect(await invoiceCount(), 1);
    });

    test('15) SQLITE_BUSY retry succeeds under dual connection contention',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b7_busy_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(
              name: Value('Busy Product'),
              currentStock: Value(5),
            ),
          );
      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Busy Supplier')),
          );
      final sameKey = b7PurchaseIdempotencyKey();
      final fp = PurchaseFingerprint.compute(
        supplierId: sid,
        operatorInvoiceNumber: null,
        purchaseDate: purchaseDate,
        invoiceDiscount: 0,
        total: 20,
        paidAmount: 20,
        dueDate: null,
        notes: '',
        items: [
          PurchaseFingerprintLine(productId: pid, quantity: 2, unitCost: 10),
        ],
      );
      final items = [
        {'productId': pid, 'qty': 2.0, 'cost': 10.0, 'discount': 0.0},
      ];

      final results = await Future.wait([
        PurchaseSaveService(dbA).processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          supplierId: sid,
          operatorInvoiceNumber: '',
          purchaseDate: purchaseDate,
          invoiceDiscount: 0,
          total: 20,
          paidAmount: 20,
          dueDate: null,
          notes: '',
          items: items,
        ),
        PurchaseSaveService(dbB).processSave(
          idempotencyKey: sameKey,
          fingerprintHash: fp,
          supplierId: sid,
          operatorInvoiceNumber: '',
          purchaseDate: purchaseDate,
          invoiceDiscount: 0,
          total: 20,
          paidAmount: 20,
          dueDate: null,
          notes: '',
          items: items,
        ),
      ]);

      expect(
          results.every(
              (r) => r.purchaseInvoiceId == results.first.purchaseInvoiceId),
          isTrue);
      expect(await invoiceCount(dbA), 1);
    });

    test('16) v38 -> v39 migration works', () async {
      final opened = await openSimulatedV38RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='purchase_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 39);
      expect(await idempotencyTableExists(migrated), isTrue);
      expect(await idempotencyIndexExists(migrated), isTrue);
    });

    test('17) fresh v39 database works', () async {
      expect(db.schemaVersion, 39);
      expect(await idempotencyTableExists(db), isTrue);
      expect(await idempotencyIndexExists(db), isTrue);
    });

    test('19) paid/debt purchase semantics preserved', () async {
      final result = await savePurchase(total: 100, paidAmount: 35);
      final invoice = await (db.select(db.purchaseInvoices)
            ..where((i) => i.id.equals(result.purchaseInvoiceId)))
          .getSingle();
      expect(invoice.paidAmount, closeTo(35, 0.001));
      expect(invoice.debtAmount, closeTo(65, 0.001));
      expect(await supplierBalance(), closeTo(65, 0.001));
      expect(await purchaseCashLedgerCount(), 1);
    });

    test('20) auto invoice number stable across replay', () async {
      final key = b7PurchaseIdempotencyKey();
      final fp = fingerprintFor();
      final first = await savePurchase(key: key, fingerprint: fp);
      final second = await savePurchase(key: key, fingerprint: fp);
      expect(second.purchaseInvoiceNumber, first.purchaseInvoiceNumber);
      expect(second.purchaseInvoiceNumber, startsWith('PUR-'));
    });

    test('21) operator invoice number participates in fingerprint', () async {
      final key = b7PurchaseIdempotencyKey();
      const manualNumber = 'INV-OPERATOR-001';
      final fp = fingerprintFor(operatorInvoiceNumber: manualNumber);
      final first = await savePurchase(
        key: key,
        fingerprint: fp,
        operatorInvoiceNumber: manualNumber,
      );
      expect(first.purchaseInvoiceNumber, manualNumber);

      await expectLater(
        savePurchase(
          key: key,
          fingerprint: fingerprintFor(operatorInvoiceNumber: 'INV-OTHER'),
          operatorInvoiceNumber: 'INV-OTHER',
        ),
        throwsA(isA<PurchaseIdempotencyConflictException>()),
      );
      expect(await invoiceCount(), 1);
    });

    test('22) B2-B6 regression sentinel after schema v39', () async {
      final regressionDb = AppDatabase.test();
      addTearDown(() async => regressionDb.close());

      expect(regressionDb.schemaVersion, 39);

      // B4 — unique sales invoice index preserved after v39 migration.
      final b4Index = await regressionDb.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='uq_sales_invoices_invoice_number'",
      ).get();
      expect(b4Index, isNotEmpty);

      // B5 — POS sale idempotency replay still works on v39.
      final b5ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B7 Regression Product'),
              barcode: Value('B7-REG-PROD'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
      final b5CustomerId = await regressionDb.into(regressionDb.customers).insert(
            const CustomersCompanion(
              name: Value('B7 Regression Customer'),
              creditLimit: Value(100),
            ),
          );
      final b5SaleService = PosSaleService(regressionDb);
      final b5Payment = PaymentInfo(
        method: 'CASH',
        idempotencyKey: _b7RegressionPosSaleKey(),
        cashPaid: 10,
      );
      final b5Product = ProductModel(
        id: b5ProductId,
        name: 'B7 Regression Product',
        barcode: 'B7-REG-PROD',
        costPrice: 5,
        sellPrice: 10,
      );
      final b5Fingerprint = PosSaleFingerprint.compute(
        sessionId: 1,
        cartSlotId: 1,
        items: [CartItem(product: b5Product, quantity: 1, unitPrice: 10)],
        invoiceDiscount: 0,
        loyaltyPointsUsed: b5Payment.pointsUsed,
        loyaltyDiscount: b5Payment.loyaltyDiscount,
        customerId: b5CustomerId,
        payment: b5Payment,
      );
      final b5First = await b5SaleService.processSale(
        idempotencyKey: b5Payment.idempotencyKey,
        fingerprintHash: b5Fingerprint,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
          debtAmount: const Value(0),
          customerId: Value(b5CustomerId),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(b5ProductId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(5),
            total: const Value(10),
          ),
        ],
        debtAmount: 0,
        netSaleTotal: 10,
      );
      final b5Second = await b5SaleService.processSale(
        idempotencyKey: b5Payment.idempotencyKey,
        fingerprintHash: b5Fingerprint,
        invoice: SalesInvoicesCompanion(
          subtotal: const Value(10),
          total: const Value(10),
          paymentMethod: const Value('CASH'),
          cashPaid: const Value(10),
          debtAmount: const Value(0),
          customerId: Value(b5CustomerId),
        ),
        items: [
          SaleItemsCompanion(
            productId: Value(b5ProductId),
            quantity: const Value(1),
            unitPrice: const Value(10),
            unitCost: const Value(5),
            total: const Value(10),
          ),
        ],
        debtAmount: 0,
        netSaleTotal: 10,
      );
      expect(b5Second.idempotentReplay, isTrue);
      expect(b5Second.invoiceId, b5First.invoiceId);
      expect((await regressionDb.select(regressionDb.salesInvoices).get()).length,
          1);

      // B6 — customer payment idempotency replay still works on v39.
      final b6CustomerId = await regressionDb.into(regressionDb.customers).insert(
            const CustomersCompanion(name: Value('B7 Regression Payer')),
          );
      final b6ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B7 Regression Pay Product'),
              barcode: Value('B7-REG-PAY'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      final b6InvoiceId = await regressionDb.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('B7-REG-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(100),
          total: const Value(100),
          debtAmount: const Value(100),
          customerId: Value(b6CustomerId),
          paymentMethod: const Value('DEBT'),
        ),
        items: [
          {'productId': b6ProductId, 'qty': 1.0, 'price': 100, 'cost': 1.0},
        ],
      );
      await regressionDb.customerAccountsDao.recordSale(
        customerId: b6CustomerId,
        amount: 100,
        invoiceId: b6InvoiceId,
        note: 'B7 regression seed debt',
      );
      final b6PaymentService = CustomerAccountService(regressionDb);
      final b6Key = b6PaymentIdempotencyKey();
      final b6First = await b6PaymentService.processPayment(
        idempotencyKey: b6Key,
        customerId: b6CustomerId,
        amount: 40,
        note: 'دفعة نقدية',
      );
      final b6Second = await b6PaymentService.processPayment(
        idempotencyKey: b6Key,
        customerId: b6CustomerId,
        amount: 40,
        note: 'دفعة نقدية',
      );
      expect(b6Second.idempotentReplay, isTrue);
      expect(b6Second.customerTransactionId, b6First.customerTransactionId);
      expect(
        (await (regressionDb.select(regressionDb.customerTransactions)
                  ..where((t) =>
                      t.customerId.equals(b6CustomerId) &
                      t.type.equals('PAYMENT')))
                .get())
            .length,
        1,
      );

      // B3 — supplier overpayment guard still rejects excess payments on v39.
      final b3SupplierId = await regressionDb.into(regressionDb.suppliers).insert(
            const SuppliersCompanion(name: Value('B7 Regression Supplier')),
          );
      final b3ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(name: Value('B7 Regression Supplier Part')),
          );
      await regressionDb.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(b3SupplierId),
          purchaseDate: Value(DateTime(2026, 3, 1)),
          total: const Value(100),
          paidAmount: const Value(0),
          debtAmount: const Value(100),
        ),
        items: [
          {'productId': b3ProductId, 'qty': 20.0, 'cost': 5.0},
        ],
      );
      final b3PaymentService = SupplierAccountService(regressionDb);
      await expectLater(
        b3PaymentService.processPayment(
          supplierId: b3SupplierId,
          amount: 110,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );
      expect(
        await regressionDb.supplierAccountsDao
            .calculateBalanceFromTransactions(b3SupplierId),
        closeTo(100, 0.001),
      );

      // B2 — credit limit enforcement still rejects over-limit debt sales on v39.
      final b2CustomerId = await regressionDb.into(regressionDb.customers).insert(
            const CustomersCompanion(
              name: Value('B7 Regression Credit Customer'),
              creditLimit: Value(100),
            ),
          );
      final b2ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B7 Regression Credit Product'),
              barcode: Value('B7-REG-CREDIT'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      final b2SaleService = PosSaleService(regressionDb);
      await expectLater(
        b2SaleService.processSale(
          idempotencyKey: _b7RegressionPosSaleKey(),
          fingerprintHash: _b7RegressionCreditFingerprint,
          invoice: SalesInvoicesCompanion(
            subtotal: const Value(101),
            total: const Value(101),
            paymentMethod: const Value('DEBT'),
            cashPaid: const Value(0),
            debtAmount: const Value(101),
            customerId: Value(b2CustomerId),
          ),
          items: [
            SaleItemsCompanion(
              productId: Value(b2ProductId),
              quantity: const Value(1),
              unitPrice: const Value(101),
              unitCost: const Value(5),
              total: const Value(101),
            ),
          ],
          debtAmount: 101,
          netSaleTotal: 101,
        ),
        throwsA(isA<CreditLimitExceededException>()),
      );
      expect(
        await regressionDb.customerAccountsDao
            .calculateBalanceFromTransactions(b2CustomerId),
        closeTo(0, 0.001),
      );
    });

  });

  group('B7 purchase save idempotency case 18 ui', () {
    late AppDatabase uiDb;
    late int uiProductId;

    setUpAll(() async {
      uiDb = AppDatabase.test();
      uiProductId = await uiDb.into(uiDb.products).insert(
            const ProductsCompanion(
              name: Value('B7 UI Product'),
              barcode: Value('B7-UI-PROD'),
              currentStock: Value(50),
              costPrice: Value(10),
            ),
          );
    });

    tearDownAll(() async => uiDb.close());

    testWidgets('18) in-flight submission guard blocks duplicate intent',
        (tester) async {
      final saveGate = Completer<void>();
      addTearDown(() {
        if (!saveGate.isCompleted) {
          saveGate.complete();
        }
      });

      final spyService = _CountingPurchaseSaveService(
        uiDb,
        saveGate: saveGate,
        stubResponse: true,
      );
      final purchasesRepo = PurchasesRepository(uiDb, spyService);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_TestAuthNotifier.new),
          purchaseSaveServiceProvider.overrideWithValue(spyService),
          purchasesRepositoryProvider.overrideWithValue(purchasesRepo),
          purchasesNotifierProvider.overrideWith(_TestPurchasesNotifier.new),
          suppliersRepositoryProvider
              .overrideWithValue(SuppliersRepository(uiDb)),
          suppliersStreamProvider.overrideWith(
            (ref) => Stream.value(const <SupplierModel>[]),
          ),
          supplierAccountsDaoProvider
              .overrideWithValue(uiDb.supplierAccountsDao),
          productsRepositoryProvider.overrideWithValue(ProductsRepository(uiDb)),
          productsNotifierProvider.overrideWith(_TestProductsNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      container.read(purchaseFormProvider.notifier)
        ..reset()
        ..addItem(
          PurchaseItemModel(
            productId: uiProductId,
            productName: 'B7 UI Product',
            quantity: 10,
            unitCost: 10,
            total: 100,
          ),
        );

      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: PurchaseFormScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      tester.takeException();

      final saveButton = find.widgetWithText(ElevatedButton, 'حفظ الفاتورة');
      expect(saveButton, findsOneWidget);
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);

      await tester.tap(saveButton);
      await tester.pump();
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      tester.takeException();

      expect(spyService.processSaveCalls, 1,
          reason: 'PurchaseFormScreen duplicate taps must invoke save once');

      saveGate.complete();
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }
    });
  });

  group('B7 fingerprint helpers', () {
    test('fingerprint is deterministic', () {
      final purchaseDate = DateTime(2026, 10, 1);
      const productId = 1;
      const supplierId = 1;
      final a = PurchaseFingerprint.compute(
        supplierId: supplierId,
        operatorInvoiceNumber: null,
        purchaseDate: purchaseDate,
        invoiceDiscount: 0,
        total: 100,
        paidAmount: 25,
        dueDate: null,
        notes: '',
        items: const [
          PurchaseFingerprintLine(
            productId: productId,
            quantity: 10,
            unitCost: 10,
          ),
        ],
      );
      final b = PurchaseFingerprint.compute(
        supplierId: supplierId,
        operatorInvoiceNumber: null,
        purchaseDate: purchaseDate,
        invoiceDiscount: 0,
        total: 100,
        paidAmount: 25,
        dueDate: null,
        notes: '',
        items: const [
          PurchaseFingerprintLine(
            productId: productId,
            quantity: 10,
            unitCost: 10,
          ),
        ],
      );
      expect(a, b);
    });
  });
}
