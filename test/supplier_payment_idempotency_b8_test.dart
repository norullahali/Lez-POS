import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_account_service.dart';
import 'package:lez_pos/core/services/credit_limit_exception.dart';
import 'package:lez_pos/core/services/pos_sale_fingerprint.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/features/pos/models/cart_item.dart';
import 'package:lez_pos/features/products/models/product_model.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_payment_exceeds_payable_exception.dart';
import 'package:lez_pos/core/services/supplier_payment_fingerprint.dart';
import 'package:lez_pos/core/services/supplier_payment_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/supplier_payment_result.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/suppliers/models/supplier_model.dart';
import 'package:lez_pos/features/suppliers/providers/supplier_accounts_provider.dart';
import 'package:lez_pos/features/suppliers/providers/suppliers_provider.dart';
import 'package:lez_pos/features/suppliers/screens/supplier_payments_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/customer_payment_test_keys.dart';
import 'support/supplier_payment_test_keys.dart';

Future<({sqlite3.Database rawDb, String path})> openSimulatedV39RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b8_v39_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
      'DROP TABLE IF EXISTS supplier_payment_idempotency');
  await bootstrap.customStatement('PRAGMA user_version = 39');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 39);
  return (rawDb: rawDb, path: dbPath);
}

class _CountingSupplierAccountService extends SupplierAccountService {
  _CountingSupplierAccountService(
    super.db, {
    Completer<void>? paymentGate,
    this.deferToSuper = true,
  })  : _paymentGate = paymentGate;

  final Completer<void>? _paymentGate;
  bool throwConflict = false;
  bool deferToSuper;
  int processPaymentCalls = 0;
  final List<String> keysUsed = [];

  @override
  Future<SupplierPaymentResult> processPayment({
    required String idempotencyKey,
    required int supplierId,
    required double amount,
    String? note,
  }) async {
    processPaymentCalls++;
    keysUsed.add(idempotencyKey);
    if (throwConflict) {
      throw const SupplierPaymentIdempotencyConflictException();
    }
    if (_paymentGate != null) {
      await _paymentGate!.future;
    }
    if (!deferToSuper) {
      return const SupplierPaymentResult(
        supplierTransactionId: 1,
        idempotentReplay: false,
      );
    }
    return super.processPayment(
      idempotencyKey: idempotencyKey,
      supplierId: supplierId,
      amount: amount,
      note: note,
    );
  }
}

List<Override> _supplierPaymentUiOverrides({
  required _CountingSupplierAccountService spyService,
  required AppDatabase uiDb,
  required int uiSupplierId,
}) {
  return [
    supplierAccountServiceProvider.overrideWithValue(spyService),
    suppliersNotifierProvider.overrideWith(
      () => _TestSuppliersNotifier([
        SupplierModel(id: uiSupplierId, name: 'B8 UI Supplier'),
      ]),
    ),
    supplierAccountsDaoProvider.overrideWithValue(uiDb.supplierAccountsDao),
    supplierBalanceProvider.overrideWith(
      (ref, supplierId) => Stream.value(1000.0),
    ),
  ];
}

class _TestSuppliersNotifier extends SuppliersNotifier {
  _TestSuppliersNotifier(this._suppliers);

  final List<SupplierModel> _suppliers;

  @override
  Future<List<SupplierModel>> build() async => _suppliers;
}

Future<void> _pumpUntilPaymentForm(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final saveButton = find.widgetWithText(ElevatedButton, 'حفظ');
    if (saveButton.evaluate().isEmpty) continue;
    final button = tester.widget<ElevatedButton>(saveButton);
    if (button.onPressed != null &&
        find.byType(TextField).evaluate().length >= 2) {
      return;
    }
  }
  fail('Supplier payment form did not load');
}

Widget _supplierPaymentScreenShell({
  required int supplierId,
}) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SupplierPaymentsScreen(supplierId: supplierId),
    ),
  );
}

Widget _supplierPaymentTestApp({
  required ProviderContainer container,
  required int supplierId,
  String initialLocation = '/supplier-payment',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/supplier-payment',
        builder: (context, state) =>
            _supplierPaymentScreenShell(supplierId: supplierId),
      ),
      GoRoute(
        path: '/suppliers',
        builder: (context, state) =>
            _supplierPaymentScreenShell(supplierId: supplierId),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<int> _seedUiSupplier(AppDatabase uiDb) async {
  final uiSupplierId = await uiDb.into(uiDb.suppliers).insert(
        const SuppliersCompanion(name: Value('B8 UI Supplier')),
      );
  final pid = await uiDb.into(uiDb.products).insert(
        const ProductsCompanion(name: Value('B8 UI Part')),
      );
  await uiDb.purchasesDao.savePurchaseInvoice(
    header: PurchaseInvoicesCompanion(
      supplierId: Value(uiSupplierId),
      purchaseDate: Value(DateTime(2026, 3, 1)),
      total: const Value(1000),
      paidAmount: const Value(0),
      debtAmount: const Value(1000),
    ),
    items: [
      {'productId': pid, 'qty': 200.0, 'cost': 5.0},
    ],
  );
  return uiSupplierId;
}

void main() {
  late AppDatabase db;
  late SupplierAccountService paymentService;
  late int supplierId;
  late int productId;

  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  setUp(() async {
    db = AppDatabase.test();
    paymentService = SupplierAccountService(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('B8 Payment Supplier')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(name: Value('B8 Part')),
        );

    await db.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(supplierId),
        purchaseDate: Value(DateTime(2026, 3, 1)),
        total: const Value(1000),
        paidAmount: const Value(0),
        debtAmount: const Value(1000),
      ),
      items: [
        {'productId': productId, 'qty': 200.0, 'cost': 5.0},
      ],
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance([AppDatabase? database, int? sid]) {
    final target = database ?? db;
    return target.supplierAccountsDao
        .calculateBalanceFromTransactions(sid ?? supplierId);
  }

  Future<int> paymentTxnCount([AppDatabase? database, int? sid]) async {
    final target = database ?? db;
    return (await (target.select(target.supplierTransactions)
          ..where((t) =>
              t.supplierId.equals(sid ?? supplierId) & t.type.equals('PAYMENT')))
        .get())
        .length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.supplierPaymentIdempotency).get()).length;
  }

  Future<int> logCount([AppDatabase? database]) async =>
      (await (database ?? db).select((database ?? db).logsTable).get()).length;

  Future<int> supplierPaymentLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await FinancialLedgerRepository(target).getEntries(ledgerFilter))
        .entries
        .where((e) => e.eventType == CashLedgerEventType.supplierPayment)
        .length;
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='supplier_payment_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  group('B8 supplier payment idempotency', () {
    test('1) first payment succeeds', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      final result = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 500,
      );

      expect(result.idempotentReplay, isFalse);
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await balance(), closeTo(500, 0.001));
    });

    test('2) same key + same fingerprint replays', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 500,
      );
      final replay = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 500,
      );
      expect(replay.idempotentReplay, isTrue);
    });

    test('3) replay returns same supplierTransactionId', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      final first = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 400,
      );
      final second = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 400,
      );
      expect(second.supplierTransactionId, first.supplierTransactionId);
    });

    test('4) replay creates no second PAYMENT row', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 300,
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 300,
      );
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('5) replay creates no second ledger event', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 250,
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 250,
      );
      expect(await supplierPaymentLedgerCount(), 1);
    });

    test('6) same key + changed amount conflicts', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 600,
      );
      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          supplierId: supplierId,
          amount: 500,
        ),
        throwsA(isA<SupplierPaymentIdempotencyConflictException>()),
      );
      expect(await paymentTxnCount(), 1);
    });

    test('7) same key + changed supplier conflicts', () async {
      final otherSupplier = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Other Supplier')),
          );
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 100,
      );
      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          supplierId: otherSupplier,
          amount: 100,
        ),
        throwsA(isA<SupplierPaymentIdempotencyConflictException>()),
      );
      expect(await paymentTxnCount(), 1);
    });

    test('8) same key + changed note conflicts', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 100,
        note: 'first note',
      );
      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          supplierId: supplierId,
          amount: 100,
          note: 'second note',
        ),
        throwsA(isA<SupplierPaymentIdempotencyConflictException>()),
      );
      expect(await paymentTxnCount(), 1);
    });

    test('9) different keys remain independent', () async {
      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 400,
      );
      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: supplierId,
        amount: 400,
      );
      expect(await paymentTxnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      expect(await balance(), closeTo(200, 0.001));
    });

    test('10) B3 overpayment still rejects', () async {
      await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 3, 2)),
          total: const Value(100),
          paidAmount: const Value(0),
          debtAmount: const Value(100),
        ),
        items: [
          {'productId': productId, 'qty': 20.0, 'cost': 5.0},
        ],
      );
      final payable500Supplier = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Payable 500')),
          );
      await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(payable500Supplier),
          purchaseDate: Value(DateTime(2026, 3, 3)),
          total: const Value(500),
          paidAmount: const Value(0),
          debtAmount: const Value(500),
        ),
        items: [
          {'productId': productId, 'qty': 100.0, 'cost': 5.0},
        ],
      );

      await expectLater(
        paymentService.processPayment(
          idempotencyKey: b8SupplierPaymentIdempotencyKey(),
          supplierId: payable500Supplier,
          amount: 600,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );
      expect(await paymentTxnCount(db, payable500Supplier), 0);
      expect(await idempotencyRowCount(), 0);
    });

    test('11) dual-connection same-key concurrency', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b8_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Concurrent Supplier')),
          );
      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(name: Value('Concurrent Part')),
          );
      await dbA.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(sid),
          purchaseDate: Value(DateTime(2026, 3, 1)),
          total: const Value(500),
          paidAmount: const Value(0),
          debtAmount: const Value(500),
        ),
        items: [
          {'productId': pid, 'qty': 100.0, 'cost': 5.0},
        ],
      );

      final serviceA = SupplierAccountService(dbA);
      final serviceB = SupplierAccountService(dbB);
      final sameKey = b8SupplierPaymentIdempotencyKey();
      final logsBefore = await logCount(dbA);
      final ledgerBefore = await supplierPaymentLedgerCount(dbA);

      final outcomes = await Future.wait([
        serviceA.processPayment(
          idempotencyKey: sameKey,
          supplierId: sid,
          amount: 400,
        ),
        serviceB.processPayment(
          idempotencyKey: sameKey,
          supplierId: sid,
          amount: 400,
        ),
      ]);

      expect(await paymentTxnCount(dbA, sid), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(await logCount(dbA) - logsBefore, 1);
      expect(await supplierPaymentLedgerCount(dbA) - ledgerBefore, 1);
      expect(outcomes.map((r) => r.supplierTransactionId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('12) losing seal race rolls back payment and log', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      final failingService = SupplierAccountService(
        db,
        preSealHook: () async {
          throw Exception('forced seal failure');
        },
      );

      await expectLater(
        failingService.processPayment(
          idempotencyKey: key,
          supplierId: supplierId,
          amount: 150,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await paymentTxnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await logCount(), 0);

      final retry = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 150,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('13) SQLITE_BUSY retry succeeds under dual connection contention',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b8_busy_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final sid = await dbA.into(dbA.suppliers).insert(
            const SuppliersCompanion(name: Value('Busy Supplier')),
          );
      final pid = await dbA.into(dbA.products).insert(
            const ProductsCompanion(name: Value('Busy Part')),
          );
      await dbA.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(sid),
          purchaseDate: Value(DateTime(2026, 3, 1)),
          total: const Value(500),
          paidAmount: const Value(0),
          debtAmount: const Value(500),
        ),
        items: [
          {'productId': pid, 'qty': 100.0, 'cost': 5.0},
        ],
      );

      final sameKey = b8SupplierPaymentIdempotencyKey();
      final results = await Future.wait([
        SupplierAccountService(dbA).processPayment(
          idempotencyKey: sameKey,
          supplierId: sid,
          amount: 400,
        ),
        SupplierAccountService(dbB).processPayment(
          idempotencyKey: sameKey,
          supplierId: sid,
          amount: 400,
        ),
      ]);

      expect(results.map((r) => r.supplierTransactionId).toSet().length, 1);
      expect(await paymentTxnCount(dbA, sid), 1);
    });

    test('14) migration v39 -> v40 creates table', () async {
      final opened = await openSimulatedV39RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='supplier_payment_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 45);
      expect(await idempotencyTableExists(migrated), isTrue);
    });

    test('15) fresh v41 schema includes table', () async {
      expect(db.schemaVersion, 45);
      expect(await idempotencyTableExists(db), isTrue);
    });

    test('17) failure before seal preserves key; retry succeeds once', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      final failingService = SupplierAccountService(
        db,
        preSealHook: () async {
          throw Exception('forced seal failure');
        },
      );

      await expectLater(
        failingService.processPayment(
          idempotencyKey: key,
          supplierId: supplierId,
          amount: 75,
        ),
        throwsA(isA<Exception>()),
      );

      final retry = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 75,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await paymentTxnCount(), 1);
    });

    test('21) replay creates no second log row', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 120,
      );
      final logsAfterFirst = await logCount();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 120,
      );
      expect(await logCount(), logsAfterFirst);
    });

    test('22) empty vs null note normalize identically', () async {
      final hashNull = SupplierPaymentFingerprint.compute(
        supplierId: supplierId,
        amount: 50,
        note: SupplierPaymentFingerprint.normalizeNote(null),
      );
      final hashEmpty = SupplierPaymentFingerprint.compute(
        supplierId: supplierId,
        amount: 50,
        note: SupplierPaymentFingerprint.normalizeNote(''),
      );
      final hashWhitespace = SupplierPaymentFingerprint.compute(
        supplierId: supplierId,
        amount: 50,
        note: SupplierPaymentFingerprint.normalizeNote('   '),
      );
      expect(hashNull, hashEmpty);
      expect(hashEmpty, hashWhitespace);

      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 50,
        note: null,
      );
      final replay = await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 50,
        note: '   ',
      );
      expect(replay.idempotentReplay, isTrue);
    });

    test('23) B3 scenario 4: two keys 400 + 400 on payable 500', () async {
      final sid = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Scenario 4 Supplier')),
          );
      await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(sid),
          purchaseDate: Value(DateTime(2026, 3, 4)),
          total: const Value(500),
          paidAmount: const Value(0),
          debtAmount: const Value(500),
        ),
        items: [
          {'productId': productId, 'qty': 100.0, 'cost': 5.0},
        ],
      );

      await paymentService.processPayment(
        idempotencyKey: b8SupplierPaymentIdempotencyKey(),
        supplierId: sid,
        amount: 400,
      );
      await expectLater(
        paymentService.processPayment(
          idempotencyKey: b8SupplierPaymentIdempotencyKey(),
          supplierId: sid,
          amount: 400,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );
      expect(await paymentTxnCount(db, sid), 1);
      expect(await balance(db, sid), closeTo(100, 0.001));
    });

    test('24) balance correct after replay', () async {
      final key = b8SupplierPaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 500,
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        supplierId: supplierId,
        amount: 500,
      );
      expect(await balance(), closeTo(500, 0.001));
    });

    test('20) B2-B7 regression sentinel on v41', () async {
      final regressionDb = AppDatabase.test();
      addTearDown(() async => regressionDb.close());
      expect(regressionDb.schemaVersion, 45);

      final b4Index = await regressionDb.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='uq_sales_invoices_invoice_number'",
      ).get();
      expect(b4Index, isNotEmpty);

      final b5ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B8 Regression Product'),
              barcode: Value('B8-REG-PROD'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
      final b5CustomerId = await regressionDb.into(regressionDb.customers).insert(
            const CustomersCompanion(
              name: Value('B8 Regression Customer'),
              creditLimit: Value(100),
            ),
          );
      final b5SaleService = PosSaleService(regressionDb);
      final b5Payment = PaymentInfo(
        method: 'CASH',
        idempotencyKey: b6PaymentIdempotencyKey(),
        cashPaid: 10,
      );
      final b5Product = ProductModel(
        id: b5ProductId,
        name: 'B8 Regression Product',
        barcode: 'B8-REG-PROD',
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

      final b6CustomerId = await regressionDb.into(regressionDb.customers).insert(
            const CustomersCompanion(name: Value('B8 Regression Payer')),
          );
      final b6ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B8 Regression Pay Product'),
              barcode: Value('B8-REG-PAY'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      final b6InvoiceId = await regressionDb.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('B8-REG-${DateTime.now().microsecondsSinceEpoch}'),
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
        note: 'B8 regression seed debt',
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

      final b3SupplierId = await regressionDb.into(regressionDb.suppliers).insert(
            const SuppliersCompanion(name: Value('B8 Regression Supplier')),
          );
      final b3ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(name: Value('B8 Regression Supplier Part')),
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
      await expectLater(
        SupplierAccountService(regressionDb).processPayment(
          idempotencyKey: b8SupplierPaymentIdempotencyKey(),
          supplierId: b3SupplierId,
          amount: 110,
        ),
        throwsA(isA<SupplierPaymentExceedsPayableException>()),
      );

      final b2CustomerId = await regressionDb.into(regressionDb.customers).insert(
            const CustomersCompanion(
              name: Value('B8 Regression Credit Customer'),
              creditLimit: Value(100),
            ),
          );
      final b2ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B8 Regression Credit Product'),
              barcode: Value('B8-REG-CREDIT'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      await expectLater(
        PosSaleService(regressionDb).processSale(
          idempotencyKey: b6PaymentIdempotencyKey(),
          fingerprintHash: 'b8-b2-regression-credit-fingerprint',
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

  group('B8 supplier payment idempotency case 16 ui', () {
    testWidgets('16) duplicate submit invokes processPayment once', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiSupplierId = await _seedUiSupplier(uiDb);

      final paymentGate = Completer<void>();
      addTearDown(() {
        if (!paymentGate.isCompleted) paymentGate.complete();
      });

      final spyService = _CountingSupplierAccountService(
        uiDb,
        paymentGate: paymentGate,
        deferToSuper: false,
      );

      final container = ProviderContainer(
        overrides: _supplierPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          uiSupplierId: uiSupplierId,
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _supplierPaymentTestApp(
          container: container,
          supplierId: uiSupplierId,
        ),
      );
      await _pumpUntilPaymentForm(tester);
      tester.takeException();

      await tester.enterText(find.byType(TextField).first, '100');
      final saveButton = find.widgetWithText(ElevatedButton, 'حفظ');
      await tester.tap(saveButton);
      await tester.pump();
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      tester.takeException();

      expect(spyService.processPaymentCalls, 1);

      paymentGate.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }
    });

    testWidgets('18) success clears key for next attempt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiSupplierId = await _seedUiSupplier(uiDb);

      final spyService = _CountingSupplierAccountService(
        uiDb,
        deferToSuper: false,
      );

      final container = ProviderContainer(
        overrides: _supplierPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          uiSupplierId: uiSupplierId,
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _supplierPaymentTestApp(
          container: container,
          supplierId: uiSupplierId,
        ),
      );
      await _pumpUntilPaymentForm(tester);
      tester.takeException();

      await tester.enterText(find.byType(TextField).first, '100');
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }

      await _pumpUntilPaymentForm(tester);
      tester.takeException();
      await tester.enterText(find.byType(TextField).first, '200');
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }

      expect(spyService.keysUsed.length, 2);
      expect(spyService.keysUsed[0], isNot(spyService.keysUsed[1]));
    });

    testWidgets('19) conflict clears key for next attempt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiSupplierId = await _seedUiSupplier(uiDb);

      final spyService = _CountingSupplierAccountService(
        uiDb,
        deferToSuper: false,
      )..throwConflict = true;

      final container = ProviderContainer(
        overrides: _supplierPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          uiSupplierId: uiSupplierId,
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _supplierPaymentTestApp(
          container: container,
          supplierId: uiSupplierId,
        ),
      );
      await _pumpUntilPaymentForm(tester);
      tester.takeException();

      await tester.enterText(find.byType(TextField).first, '100');
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }

      spyService.throwConflict = false;
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }

      expect(spyService.keysUsed.length, 2);
      expect(spyService.keysUsed[0], isNot(spyService.keysUsed[1]));
    });
  });
}
