import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_account_service.dart';
import 'package:lez_pos/core/services/customer_payment_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/customer_payment_result.dart';
import 'package:lez_pos/features/customers/providers/customer_accounts_provider.dart';
import 'package:lez_pos/features/customers/providers/customers_provider.dart';
import 'package:lez_pos/features/customers/customer_payment_submit_idempotency.dart';
import 'package:lez_pos/features/customers/screens/customer_payments_screen.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/pos/repositories/pos_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/customer_payment_test_keys.dart';

class _CountingCustomerAccountService extends CustomerAccountService {
  _CountingCustomerAccountService(
    super.db, {
    Completer<void>? paymentGate,
    this.deferToSuper = true,
  }) : _paymentGate = paymentGate;

  final Completer<void>? _paymentGate;
  bool throwConflict = false;
  bool throwOnce = false;
  bool deferToSuper;
  int processPaymentCalls = 0;
  final List<String> keysUsed = [];
  final List<bool> replayFlags = [];

  @override
  Future<CustomerPaymentResult> processPayment({
    required String idempotencyKey,
    required int customerId,
    required double amount,
    String? note,
  }) async {
    processPaymentCalls++;
    keysUsed.add(idempotencyKey);
    if (throwOnce) {
      throwOnce = false;
      throw Exception('forced payment failure');
    }
    if (throwConflict) {
      throw const CustomerPaymentIdempotencyConflictException();
    }
    if (_paymentGate != null) {
      await _paymentGate!.future;
    }
    if (!deferToSuper) {
      replayFlags.add(false);
      return const CustomerPaymentResult(
        customerTransactionId: 1,
        idempotentReplay: false,
      );
    }
    final result = await super.processPayment(
      idempotencyKey: idempotencyKey,
      customerId: customerId,
      amount: amount,
      note: note,
    );
    replayFlags.add(result.idempotentReplay);
    return result;
  }
}

class _TestCustomersNotifier extends CustomersNotifier {
  _TestCustomersNotifier(this._customers);

  final List<Customer> _customers;

  @override
  Future<List<Customer>> build() async => _customers;
}

Future<List<Customer>> _loadUiCustomers(AppDatabase uiDb) {
  return uiDb.select(uiDb.customers).get();
}

Future<int> _seedUiCustomer(
  AppDatabase uiDb, {
  required String name,
  double debt = 100,
}) async {
  final cid = await uiDb.into(uiDb.customers).insert(
        CustomersCompanion(name: Value(name)),
      );
  final pid = await uiDb.into(uiDb.products).insert(
        ProductsCompanion(
          name: Value('$name Product'),
          barcode: Value('B6-UI-${DateTime.now().microsecondsSinceEpoch}'),
          currentStock: const Value(100),
          costPrice: const Value(5),
        ),
      );
  final invoiceId = await uiDb.salesDao.saveSaleInvoice(
    header: SalesInvoicesCompanion(
      invoiceNumber: Value('B6-UI-${DateTime.now().microsecondsSinceEpoch}'),
      subtotal: Value(debt),
      total: Value(debt),
      debtAmount: Value(debt),
      customerId: Value(cid),
      paymentMethod: const Value('DEBT'),
    ),
    items: [
      {'productId': pid, 'qty': 1.0, 'price': debt, 'cost': 1.0},
    ],
  );
  await uiDb.customerAccountsDao.recordSale(
    customerId: cid,
    amount: debt,
    invoiceId: invoiceId,
    note: 'ui seed debt',
  );
  return cid;
}

Future<int> uiCustomerPaymentTxnCount(AppDatabase uiDb, int cid) async {
  return (await (uiDb.select(uiDb.customerTransactions)
        ..where((t) => t.customerId.equals(cid) & t.type.equals('PAYMENT')))
      .get())
      .length;
}

Future<int> uiCustomerPaymentLedgerCount(AppDatabase uiDb) async {
  final ledger = FinancialLedgerRepository(uiDb);
  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );
  return (await ledger.getEntries(ledgerFilter))
      .entries
      .where((e) => e.eventType == CashLedgerEventType.customerPayment)
      .length;
}

List<Override> _customerPaymentUiOverrides({
  required _CountingCustomerAccountService spyService,
  required AppDatabase uiDb,
  required List<Customer> customers,
}) {
  return [
    customerAccountServiceProvider.overrideWithValue(spyService),
    customersNotifierProvider.overrideWith(
      () => _TestCustomersNotifier(customers),
    ),
    customerAccountsDaoProvider.overrideWithValue(uiDb.customerAccountsDao),
    customerBalanceProvider.overrideWith(
      (ref, customerId) => Stream.value(100.0),
    ),
    customerHistoryProvider.overrideWith(
      (ref, customerId) => Stream.value(const []),
    ),
  ];
}

Finder get _customerPaymentAmountField =>
    find.byKey(const Key('customer_payment_amount_field'));

Future<void> _pumpUntilCustomerPaymentForm(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final saveButton = find.widgetWithText(ElevatedButton, 'حفظ الدفعة');
    if (saveButton.evaluate().isEmpty) continue;
    if (_customerPaymentAmountField.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Customer payment form did not load');
}

Future<void> _setCustomerPaymentForm(
  WidgetTester tester, {
  String? amount,
  String? note,
}) async {
  final element = tester.element(find.byType(CustomerPaymentsScreen));
  final state = (element as StatefulElement).state;
  (state as dynamic).setPaymentFormForTesting(amount: amount, note: note);
  await tester.pump();
}

Future<void> _enterCustomerPaymentAmount(WidgetTester tester, String amount) {
  return _setCustomerPaymentForm(tester, amount: amount);
}

/// Lets a gated [processPayment] finish after [gate] is completed, then pumps
/// frames so [_savePayment] can settle before widget-test teardown.
Future<void> _finishGatedCustomerPayment(
  WidgetTester tester,
  Completer<void> gate,
) async {
  if (!gate.isCompleted) {
    gate.complete();
  }
  await tester.runAsync(() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    tester.takeException();
  }
}

Future<void> _settleCustomerPaymentUi(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  for (var i = 0; i < 5; i++) {
    await tester.pump();
    tester.takeException();
  }
}

Future<void> _tapCustomerPaymentSave(WidgetTester tester) async {
  final saveButton = find.widgetWithText(ElevatedButton, 'حفظ الدفعة');
  await tester.tap(saveButton);
  await tester.pump();
}

Future<void> _selectUiCustomerIdForHarness(
  WidgetTester tester,
  GlobalKey<_CustomerPaymentCustomerHarnessState> harnessKey,
  int customerId,
) async {
  harnessKey.currentState!.setCustomerIdForTesting(customerId);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    tester.takeException();
  }
}

Widget _customerPaymentTestApp({
  required ProviderContainer container,
  int? initialCustomerId,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: CustomerPaymentsScreen(initialCustomerId: initialCustomerId),
        ),
      ),
    ),
  );
}

Future<void> _prepareAndPumpCustomerPaymentApp(
  WidgetTester tester, {
  required ProviderContainer container,
  int? initialCustomerId,
}) async {
  await tester.pumpWidget(
    _customerPaymentTestApp(
      container: container,
      initialCustomerId: initialCustomerId,
    ),
  );
  await _pumpUntilCustomerPaymentForm(tester);
  tester.takeException();
}

class _CustomerPaymentCustomerHarness extends StatefulWidget {
  const _CustomerPaymentCustomerHarness({
    super.key,
    required this.container,
    this.initialCustomerId,
  });

  final ProviderContainer container;
  final int? initialCustomerId;

  @override
  State<_CustomerPaymentCustomerHarness> createState() =>
      _CustomerPaymentCustomerHarnessState();
}

class _CustomerPaymentCustomerHarnessState
    extends State<_CustomerPaymentCustomerHarness> {
  final GlobalKey<_CustomerPaymentCustomerHarnessBodyState> _bodyKey =
      GlobalKey<_CustomerPaymentCustomerHarnessBodyState>();

  void setCustomerIdForTesting(int customerId) {
    _bodyKey.currentState!.setCustomerIdForTesting(customerId);
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: widget.container,
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: _CustomerPaymentCustomerHarnessBody(
              key: _bodyKey,
              initialCustomerId: widget.initialCustomerId,
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerPaymentCustomerHarnessBody extends StatefulWidget {
  const _CustomerPaymentCustomerHarnessBody({
    super.key,
    required this.initialCustomerId,
  });

  final int? initialCustomerId;

  @override
  State<_CustomerPaymentCustomerHarnessBody> createState() =>
      _CustomerPaymentCustomerHarnessBodyState();
}

class _CustomerPaymentCustomerHarnessBodyState
    extends State<_CustomerPaymentCustomerHarnessBody> {
  int? _customerId;

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
  }

  void setCustomerIdForTesting(int customerId) {
    setState(() => _customerId = customerId);
  }

  @override
  Widget build(BuildContext context) {
    return CustomerPaymentsScreen(
      key: const ValueKey('b36-customer-payment'),
      initialCustomerId: _customerId,
    );
  }
}

Future<({sqlite3.Database rawDb, String path})> openSimulatedV37RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b6_v37_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
      'DROP TABLE IF EXISTS customer_payment_idempotency');
  await bootstrap.customStatement('DROP INDEX IF EXISTS cpi_customer_created_idx');
  await bootstrap.customStatement('PRAGMA user_version = 37');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 37);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  group('B6 customer payment idempotency', () {
  late AppDatabase db;
  late CustomerAccountService paymentService;
  late int customerId;
  late int productId;

  setUp(() async {
    db = AppDatabase.test();
    paymentService = CustomerAccountService(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('B6 Payment Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B6 Product'),
            barcode: Value('B6-P'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance([AppDatabase? database, int? cid]) {
    final target = database ?? db;
    return target.customerAccountsDao.getBalance(cid ?? customerId);
  }

  Future<int> paymentTxnCount([AppDatabase? database, int? cid]) async {
    final target = database ?? db;
    return (await (target.select(target.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('PAYMENT')))
        .get())
        .length;
  }

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.customerPaymentIdempotency).get()).length;
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='customer_payment_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> idempotencyIndexExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='index' "
      "AND name='cpi_customer_created_idx'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<int> customerPaymentLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    final ledger = FinancialLedgerRepository(target);
    const ledgerFilter = CashLedgerFilter(
      page: 0,
      pageSize: 1000,
      dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
    );
    return (await ledger.getEntries(ledgerFilter))
        .entries
        .where((e) => e.eventType == CashLedgerEventType.customerPayment)
        .length;
  }

  Future<void> seedDebt({
    AppDatabase? database,
    int? cid,
    double amount = 100,
  }) async {
    final target = database ?? db;
    final customer = cid ?? customerId;
    final invoiceId = await target.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('B6-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(amount),
        total: Value(amount),
        debtAmount: Value(amount),
        customerId: Value(customer),
        paymentMethod: const Value('DEBT'),
      ),
      items: [
        {'productId': productId, 'qty': 1.0, 'price': amount, 'cost': 1.0},
      ],
    );
    await target.customerAccountsDao.recordSale(
      customerId: customer,
      amount: amount,
      invoiceId: invoiceId,
      note: 'seed debt',
    );
  }

    test('1) first payment succeeds', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      final result = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 40,
        note: 'دفعة نقدية',
      );

      expect(result.idempotentReplay, isFalse);
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await balance(), closeTo(60, 0.001));
    });

    test('2) same key replay returns same transaction ID', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      final first = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'دفعة نقدية',
      );
      final second = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'دفعة نقدية',
      );

      expect(second.idempotentReplay, isTrue);
      expect(second.customerTransactionId, first.customerTransactionId);
    });

    test('3) same key creates only one PAYMENT row', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'note',
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'note',
      );
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('4) same key + different amount -> conflict', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 20,
        note: 'note',
      );

      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 21,
          note: 'note',
        ),
        throwsA(isA<CustomerPaymentIdempotencyConflictException>()),
      );
      expect(await paymentTxnCount(), 1);
    });

    test('5) same key + different note -> conflict', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 20,
        note: 'first note',
      );

      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 20,
          note: 'second note',
        ),
        throwsA(isA<CustomerPaymentIdempotencyConflictException>()),
      );
      expect(await paymentTxnCount(), 1);
    });

    test('6) different keys + identical payment data -> two payments', () async {
      await seedDebt(amount: 200);
      await paymentService.processPayment(
        idempotencyKey: b6PaymentIdempotencyKey(),
        customerId: customerId,
        amount: 50,
        note: 'دفعة نقدية',
      );
      await paymentService.processPayment(
        idempotencyKey: b6PaymentIdempotencyKey(),
        customerId: customerId,
        amount: 50,
        note: 'دفعة نقدية',
      );

      expect(await paymentTxnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      expect(await balance(), closeTo(100, 0.001));
    });

    test('7) validation failure -> no idempotency row', () async {
      final key = b6PaymentIdempotencyKey();
      await expectLater(
        paymentService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 0,
          note: 'bad',
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await paymentTxnCount(), 0);
      expect(await idempotencyRowCount(), 0);
    });

    test('8) failure before seal -> rollback and retryable key', () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      final failingService = CustomerAccountService(
        db,
        preSealHook: () async {
          throw Exception('forced seal failure');
        },
      );

      await expectLater(
        failingService.processPayment(
          idempotencyKey: key,
          customerId: customerId,
          amount: 15,
          note: 'retry me',
        ),
        throwsA(isA<Exception>()),
      );
      expect(await paymentTxnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 15,
        note: 'retry me',
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await paymentTxnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('9) dual-connection same-key concurrency', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b6_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      final cid = await dbA.into(dbA.customers).insert(
            const CustomersCompanion(name: Value('Concurrent Payer')),
          );
      await dbA.customerAccountsDao.recordSale(
        customerId: cid,
        amount: 100,
        invoiceId: 9001,
        note: 'seed',
      );

      final serviceA = CustomerAccountService(dbA);
      final serviceB = CustomerAccountService(dbB);
      final sameKey = b6PaymentIdempotencyKey();

      final outcomes = await Future.wait([
        serviceA.processPayment(
          idempotencyKey: sameKey,
          customerId: cid,
          amount: 35,
          note: 'concurrent',
        ),
        serviceB.processPayment(
          idempotencyKey: sameKey,
          customerId: cid,
          amount: 35,
          note: 'concurrent',
        ),
      ]);

      expect(await paymentTxnCount(dbA, cid), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.customerTransactionId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('10) final customer balance correct after replay', () async {
      await seedDebt(amount: 80);
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'balance test',
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 30,
        note: 'balance test',
      );
      expect(await balance(), closeTo(50, 0.001));
    });

    test('11) financial ledger shows one CUSTOMER_PAYMENT after replay',
        () async {
      await seedDebt();
      final key = b6PaymentIdempotencyKey();
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 22,
        note: 'ledger',
      );
      await paymentService.processPayment(
        idempotencyKey: key,
        customerId: customerId,
        amount: 22,
        note: 'ledger',
      );
      expect(await customerPaymentLedgerCount(), 1);
    });

    test('12) intentional overpayment remains allowed', () async {
      await seedDebt(amount: 50);
      final result = await paymentService.processPayment(
        idempotencyKey: b6PaymentIdempotencyKey(),
        customerId: customerId,
        amount: 80,
        note: 'overpay',
      );
      expect(result.idempotentReplay, isFalse);
      expect(await balance(), closeTo(-30, 0.001));
    });

    test('13) migration v37 -> v38 creates table and index', () async {
      final opened = await openSimulatedV37RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='customer_payment_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 51);
      expect(await idempotencyTableExists(migrated), isTrue);
      expect(await idempotencyIndexExists(migrated), isTrue);
    });

    test('14) fresh schema v41 includes table and index', () async {
      expect(db.schemaVersion, 51);
      expect(await idempotencyTableExists(db), isTrue);
      expect(await idempotencyIndexExists(db), isTrue);
    });

    test('15) F6 PosRepository.settleDebt uses canonical service', () async {
      await seedDebt();
      final repo = PosRepository(db, CustomerAccountService(db));
      final key = b6PaymentIdempotencyKey();
      final result = await repo.settleDebt(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'تسوية دين من POS',
      );
      expect(result.idempotentReplay, isFalse);
      final replay = await repo.settleDebt(
        idempotencyKey: key,
        customerId: customerId,
        amount: 25,
        note: 'تسوية دين من POS',
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerTransactionId, result.customerTransactionId);
      expect(await paymentTxnCount(), 1);
    });
  });

  group('B6 customer payment idempotency ui', () {
    setUp(() {
      CustomerPaymentsScreen.suppressLiveCustomerStreamsForTesting = true;
    });

    tearDown(() {
      CustomerPaymentsScreen.suppressLiveCustomerStreamsForTesting = false;
      CustomerPaymentsScreen.failNextPostSuccessRefreshForTesting = false;
    });

    testWidgets('16) duplicate submit invokes processPayment once', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiCustomerId = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final uiCustomers = await _loadUiCustomers(uiDb);

      final paymentGate = Completer<void>();
      addTearDown(() {
        if (!paymentGate.isCompleted) paymentGate.complete();
      });

      final spyService = _CountingCustomerAccountService(
        uiDb,
        paymentGate: paymentGate,
        deferToSuper: false,
      );

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);

      await _prepareAndPumpCustomerPaymentApp(
        tester,
        container: container,
        initialCustomerId: uiCustomerId,
      );

      await _enterCustomerPaymentAmount(tester, '100');
      final saveButton = find.widgetWithText(ElevatedButton, 'حفظ الدفعة');
      await tester.tap(saveButton);
      await tester.pump();
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      tester.takeException();

      expect(spyService.processPaymentCalls, 1);

      await _finishGatedCustomerPayment(tester, paymentGate);
    });

    testWidgets('18) success clears key for next attempt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiCustomerId = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final uiCustomers = await _loadUiCustomers(uiDb);

      final spyService = _CountingCustomerAccountService(
        uiDb,
        deferToSuper: false,
      );

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);

      await _prepareAndPumpCustomerPaymentApp(
        tester,
        container: container,
        initialCustomerId: uiCustomerId,
      );

      await _enterCustomerPaymentAmount(tester, '100');
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      await _pumpUntilCustomerPaymentForm(tester);
      tester.takeException();
      await _enterCustomerPaymentAmount(tester, '200');
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      expect(spyService.keysUsed.length, 2);
      expect(spyService.keysUsed[0], isNot(spyService.keysUsed[1]));
    });

    testWidgets('19) conflict retains key for retry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiCustomerId = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final uiCustomers = await _loadUiCustomers(uiDb);
      final spyService = _CountingCustomerAccountService(
        uiDb,
        deferToSuper: false,
      )..throwConflict = true;

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);

      await _prepareAndPumpCustomerPaymentApp(
        tester,
        container: container,
        initialCustomerId: uiCustomerId,
      );

      await _enterCustomerPaymentAmount(tester, '100');
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      spyService.throwConflict = false;
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      expect(spyService.processPaymentCalls, 2);
      expect(spyService.keysUsed.length, 2);
      expect(spyService.keysUsed[0], spyService.keysUsed[1]);
    });

    testWidgets('20) stale completion after amount edit during flight',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiCustomerId = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final uiCustomers = await _loadUiCustomers(uiDb);
      final paymentGate = Completer<void>();
      addTearDown(() {
        if (!paymentGate.isCompleted) paymentGate.complete();
      });

      final spyService = _CountingCustomerAccountService(
        uiDb,
        paymentGate: paymentGate,
        deferToSuper: false,
      );

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);

      await _prepareAndPumpCustomerPaymentApp(
        tester,
        container: container,
        initialCustomerId: uiCustomerId,
      );

      await _enterCustomerPaymentAmount(tester, '100');
      await _tapCustomerPaymentSave(tester);
      await tester.pump();
      await _setCustomerPaymentForm(tester, amount: '200');

      await _finishGatedCustomerPayment(tester, paymentGate);

      expect(spyService.processPaymentCalls, 1);
      expect(
        find.textContaining('تم تسجيل دفعة بقيمة'),
        findsNothing,
      );
      expect(
        find.text('تم تجاهل نتيجة دفعة سابقة بعد تغيير البيانات.'),
        findsOneWidget,
      );
    });

    testWidgets('20b) stale completion after note edit during flight',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiCustomerId = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final uiCustomers = await _loadUiCustomers(uiDb);
      final paymentGate = Completer<void>();
      addTearDown(() {
        if (!paymentGate.isCompleted) paymentGate.complete();
      });

      final spyService = _CountingCustomerAccountService(
        uiDb,
        paymentGate: paymentGate,
        deferToSuper: false,
      );

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);

      await _prepareAndPumpCustomerPaymentApp(
        tester,
        container: container,
        initialCustomerId: uiCustomerId,
      );

      await _enterCustomerPaymentAmount(tester, '100');
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await tester.pump();
      await _setCustomerPaymentForm(tester, note: 'note changed');

      await _finishGatedCustomerPayment(tester, paymentGate);

      expect(spyService.processPaymentCalls, 1);
      expect(find.textContaining('تم تسجيل دفعة بقيمة'), findsNothing);
      expect(
        find.text('تم تجاهل نتيجة دفعة سابقة بعد تغيير البيانات.'),
        findsOneWidget,
      );
    });

    testWidgets('21) stale completion after customer change during flight',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final customerA = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final customerB = await _seedUiCustomer(uiDb, name: 'B6 UI Customer B');
      final uiCustomers = await _loadUiCustomers(uiDb);
      final paymentGate = Completer<void>();
      addTearDown(() {
        if (!paymentGate.isCompleted) paymentGate.complete();
      });

      final spyService = _CountingCustomerAccountService(
        uiDb,
        paymentGate: paymentGate,
        deferToSuper: false,
      );

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);

      final harnessKey = GlobalKey<_CustomerPaymentCustomerHarnessState>();
      await tester.pumpWidget(
        _CustomerPaymentCustomerHarness(
          key: harnessKey,
          container: container,
          initialCustomerId: null,
        ),
      );
      await _pumpUntilCustomerPaymentForm(tester);
      tester.takeException();
      await _selectUiCustomerIdForHarness(tester, harnessKey, customerA);

      await _enterCustomerPaymentAmount(tester, '100');
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await tester.pump();

      harnessKey.currentState!.setCustomerIdForTesting(customerB);
      await tester.pump();

      await _finishGatedCustomerPayment(tester, paymentGate);

      expect(spyService.processPaymentCalls, 1);
      expect(find.textContaining('تم تسجيل دفعة بقيمة'), findsNothing);
      expect(
        find.text('تم تجاهل نتيجة دفعة سابقة بعد تغيير البيانات.'),
        findsOneWidget,
      );
    });

    testWidgets('22) refresh failure then successful retry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiCustomerId = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final uiCustomers = await _loadUiCustomers(uiDb);
      final spyService = _CountingCustomerAccountService(
        uiDb,
        deferToSuper: true,
      );

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);
      addTearDown(() {
        CustomerPaymentsScreen.failNextPostSuccessRefreshForTesting = false;
      });

      await _prepareAndPumpCustomerPaymentApp(
        tester,
        container: container,
        initialCustomerId: uiCustomerId,
      );

      CustomerPaymentsScreen.failNextPostSuccessRefreshForTesting = true;
      await _enterCustomerPaymentAmount(tester, '100');
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      expect(await uiCustomerPaymentTxnCount(uiDb, uiCustomerId), 1);
      expect(await uiCustomerPaymentLedgerCount(uiDb), 1);
      expect(spyService.keysUsed.length, 1);
      expect(
        find.text('تم حفظ الدفعة، لكن تعذر تحديث العرض. أعد المحاولة.'),
        findsOneWidget,
      );

      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      expect(spyService.processPaymentCalls, 2);
      expect(spyService.replayFlags.last, isTrue);
      expect(await uiCustomerPaymentTxnCount(uiDb, uiCustomerId), 1);
      expect(await uiCustomerPaymentLedgerCount(uiDb), 1);
      expect(spyService.keysUsed[0], spyService.keysUsed[1]);
    });

    testWidgets('23) ordinary failure retry uses same key', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final uiDb = AppDatabase.test();
      final uiCustomerId = await _seedUiCustomer(uiDb, name: 'B6 UI Customer A');
      final uiCustomers = await _loadUiCustomers(uiDb);
      final spyService = _CountingCustomerAccountService(
        uiDb,
        deferToSuper: false,
      )..throwOnce = true;

      final container = ProviderContainer(
        overrides: _customerPaymentUiOverrides(
          spyService: spyService,
          uiDb: uiDb,
          customers: uiCustomers,
        ),
      );
      addTearDown(container.dispose);

      await _prepareAndPumpCustomerPaymentApp(
        tester,
        container: container,
        initialCustomerId: uiCustomerId,
      );

      await _enterCustomerPaymentAmount(tester, '100');
      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      await tester.pump();
      await _tapCustomerPaymentSave(tester);
      await _settleCustomerPaymentUi(tester);

      expect(spyService.processPaymentCalls, 2);
      expect(spyService.keysUsed.length, 2);
      expect(spyService.keysUsed[0], spyService.keysUsed[1]);
    });
  });

  group('B36 customer payment submit runner', () {
    test('skips second submit while in flight', () async {
      final runner = CustomerPaymentSubmitRunner();
      final gate = Completer<void>();
      const intent = CustomerPaymentSubmitIntent(
        customerId: 2,
        amount: 50,
        note: 'دفعة نقدية',
      );
      var calls = 0;

      final firstFuture = runner.submit(
        intent: intent,
        idempotencyKey: 'key-a',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          calls++;
          await gate.future;
          return const CustomerPaymentResult(
            customerTransactionId: 1,
            idempotentReplay: false,
          );
        },
        postSuccessRefresh: (_) async {},
      );

      final second = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-a',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          calls++;
          return const CustomerPaymentResult(
            customerTransactionId: 1,
            idempotentReplay: false,
          );
        },
        postSuccessRefresh: (_) async {},
      );

      expect(second, CustomerPaymentSubmitOutcome.skippedInFlight);
      gate.complete();
      await firstFuture;
      expect(calls, 1);
    });

    test('conflict outcome without clearing key (caller policy)', () async {
      final runner = CustomerPaymentSubmitRunner();
      const intent = CustomerPaymentSubmitIntent(
        customerId: 2,
        amount: 25,
        note: 'note',
      );

      final outcome = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-b',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          throw const CustomerPaymentIdempotencyConflictException();
        },
        postSuccessRefresh: (_) async {},
      );

      expect(outcome, CustomerPaymentSubmitOutcome.idempotencyConflict);
    });

    test('stale completion after generation change', () async {
      final runner = CustomerPaymentSubmitRunner();
      var current = true;
      const intent = CustomerPaymentSubmitIntent(
        customerId: 2,
        amount: 10,
        note: 'دفعة نقدية',
      );

      final outcome = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-c',
        isSubmitStillCurrent: () => current,
        invokeService: (_) async {
          current = false;
          return const CustomerPaymentResult(
            customerTransactionId: 3,
            idempotentReplay: false,
          );
        },
        postSuccessRefresh: (_) async {},
      );

      expect(outcome, CustomerPaymentSubmitOutcome.staleCompletion);
    });
  });
}
