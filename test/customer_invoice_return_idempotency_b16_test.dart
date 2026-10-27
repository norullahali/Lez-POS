import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/activity/activity_types.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_invoice_return_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/customer_invoice_return_fingerprint.dart';
import 'package:lez_pos/core/services/customer_invoice_return_posting_result.dart';
import 'package:lez_pos/core/services/customer_invoice_return_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/auth/permissions/permission_keys.dart';
import 'package:lez_pos/features/auth/providers/auth_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_refund_settlement_provider.dart';
import 'package:lez_pos/features/invoices/customer_invoice_return_submit_idempotency.dart';
import 'package:lez_pos/features/invoices/models/invoice_detail.dart';
import 'package:lez_pos/features/invoices/providers/invoice_history_provider.dart';
import 'package:lez_pos/features/invoices/widgets/invoice_details_dialog.dart';
import 'package:lez_pos/features/pos/providers/pos_products_provider.dart';
import 'package:lez_pos/features/products/models/product_model.dart';
import 'package:lez_pos/features/products/providers/products_provider.dart';
import 'package:lez_pos/features/returns/providers/customer_invoice_return_service_provider.dart';
import 'package:lez_pos/features/returns/providers/partial_return_provider.dart';
import 'package:lez_pos/features/returns/providers/return_analytics_provider.dart';
import 'package:lez_pos/features/returns/repositories/return_analytics_repository.dart';
import 'package:lez_pos/features/returns/screens/customer_returns_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/customer_invoice_return_posting_helpers.dart';
import 'support/customer_invoice_return_test_keys.dart';

const _b38UiInvoiceId = 88001;
const _b38UiSaleItemId = 880501;

class _CountingCustomerInvoiceReturnService
    extends CustomerInvoiceReturnService {
  _CountingCustomerInvoiceReturnService(
    this.database, {
    Completer<void>? returnGate,
  })  : _returnGate = returnGate,
        super(database);

  final AppDatabase database;
  final Completer<void>? _returnGate;
  bool throwConflict = false;
  bool throwOnce = false;
  int fullReturnCalls = 0;
  int partialReturnCalls = 0;
  final List<String> fullKeysUsed = [];
  final List<String> partialKeysUsed = [];
  List<CustomerInvoicePartialReturnLine>? lastPartialLines;

  static const CustomerInvoiceReturnPostingResult _stubFull =
      CustomerInvoiceReturnPostingResult(
    customerReturnId: 1,
    returnType: CustomerInvoiceReturnType.full,
    executionPath: CustomerInvoiceExecutionPath.fullFresh,
    primaryReferenceId: 1,
    idempotentReplay: false,
  );

  static const CustomerInvoiceReturnPostingResult _stubPartial =
      CustomerInvoiceReturnPostingResult(
    customerReturnId: 2,
    returnType: CustomerInvoiceReturnType.partial,
    executionPath: CustomerInvoiceExecutionPath.partialBatch,
    primaryReferenceId: 2,
    idempotentReplay: false,
  );

  @override
  Future<CustomerInvoiceReturnPostingResult> processFullReturn({
    required String idempotencyKey,
    required int saleInvoiceId,
    required int returnedByUserId,
    required String note,
  }) async {
    fullReturnCalls++;
    fullKeysUsed.add(idempotencyKey);
    if (throwOnce) {
      throwOnce = false;
      throw Exception('forced full return failure');
    }
    if (throwConflict) {
      throw const CustomerInvoiceReturnIdempotencyConflictException();
    }
    if (_returnGate != null) {
      await _returnGate!.future;
    }
    return _stubFull;
  }

  @override
  Future<CustomerInvoiceReturnPostingResult> processPartialReturn({
    required String idempotencyKey,
    required int saleInvoiceId,
    required List<CustomerInvoicePartialReturnLine> lines,
    required int returnedByUserId,
    String? note,
  }) async {
    partialReturnCalls++;
    partialKeysUsed.add(idempotencyKey);
    lastPartialLines = List<CustomerInvoicePartialReturnLine>.from(lines);
    if (throwOnce) {
      throwOnce = false;
      throw Exception('forced partial return failure');
    }
    if (throwConflict) {
      throw const CustomerInvoiceReturnIdempotencyConflictException();
    }
    if (_returnGate != null) {
      await _returnGate!.future;
    }
    return _stubPartial;
  }
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._user);

  final User _user;

  @override
  FutureOr<AuthState> build() async => AuthState(
        user: _user,
        permissions: const [PermissionKeys.posFullRefund],
      );
}

class _NoOpRecentActivityNotifier extends RecentActivityNotifier {
  @override
  RecentActivityState build() => RecentActivityState.empty;

  @override
  Future<void> refresh() async {}
}

class _EmptyProductsNotifier extends ProductsNotifier {
  @override
  Future<List<ProductModel>> build() async => const [];
}

class _TestPosProductsNotifier extends PosProductsNotifier {
  @override
  Future<PosProductsState> build() async => PosProductsState(
        productsMap: const {},
        barcodeIndex: const {},
        isFullyLoaded: true,
      );
}

User _b38TestUser() => User(
      id: 1,
      fullName: 'B38 Cashier',
      username: 'b38cashier',
      passwordHash: 'hash',
      roleId: 1,
      isActive: true,
      refundLimit: 100000,
      createdAt: DateTime(2026, 1, 1),
    );

InvoiceDetailData _b38InvoiceDetail({
  required int customerId,
  double lineQty = 10,
}) {
  return InvoiceDetailData(
    header: InvoiceDetailHeader(
      id: _b38UiInvoiceId,
      invoiceNumber: 'B38-INV',
      saleDate: DateTime(2026, 3, 1),
      customerId: customerId,
      customerName: 'B38 Customer',
      cashierName: 'Cashier',
      paymentMethod: 'DEBT',
      invoiceStatus: InvoiceLifecycleStatus.completed,
      subtotal: lineQty * 10,
      discountTotal: 0,
      total: lineQty * 10,
      cashPaid: 0,
      cardPaid: 0,
      changeAmount: 0,
    ),
    lines: [
      InvoiceDetailLine(
        id: _b38UiSaleItemId,
        productId: 1,
        productName: 'B38 Product',
        quantity: lineQty,
        unitPrice: 10,
        unitCost: 5,
        discount: 0,
        lineTotal: lineQty * 10,
      ),
    ],
    showTax: false,
  );
}

Future<void> _seedB38UiInvoice(AppDatabase uiDb, int customerId) async {
  final productId = await uiDb.into(uiDb.products).insert(
        const ProductsCompanion(
          name: Value('B38 UI Product'),
          currentStock: Value(100),
          costPrice: Value(5),
          sellPrice: Value(10),
        ),
      );
  await uiDb.salesDao.saveSaleInvoice(
    header: SalesInvoicesCompanion(
      id: const Value(_b38UiInvoiceId),
      invoiceNumber: const Value('B38-UI-INV'),
      subtotal: const Value(100),
      total: const Value(100),
      debtAmount: const Value(100),
      customerId: Value(customerId),
      paymentMethod: const Value('DEBT'),
    ),
    items: [
      {
        'productId': productId,
        'qty': 10.0,
        'price': 10.0,
        'cost': 5.0,
      },
    ],
  );
}

Future<void> _pumpUntilB38InvoiceLoaded(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
  }
  expect(find.textContaining('B38-INV'), findsWidgets);
}

Future<void> _finishGatedInvoiceReturn(
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
  for (var i = 0; i < 8; i++) {
    await tester.pump();
    tester.takeException();
  }
}

List<Override> _b38UiOverrides({
  required InvoiceDetailData detail,
  required _CountingCustomerInvoiceReturnService spy,
  required User user,
}) {
  return [
    invoiceDetailProvider(_b38UiInvoiceId).overrideWith((ref) async => detail),
    invoicePartialReturnQtysProvider(_b38UiInvoiceId)
        .overrideWith((ref) async => <int, double>{}),
    invoiceLinkedCustomerReturnProvider(_b38UiInvoiceId)
        .overrideWith((ref) async => null),
    customerInvoiceReturnServiceProvider.overrideWithValue(spy),
    authProvider.overrideWith(() => _TestAuthNotifier(user)),
    customerAvailableCreditProvider(detail.header.customerId!)
        .overrideWith((ref) async => 0),
    partialReturnServiceProvider.overrideWith(
      (ref) => PartialReturnService(spy.database),
    ),
    returnAnalyticsRepositoryProvider.overrideWithValue(
      ReturnAnalyticsRepository(spy.database),
    ),
    recentActivityProvider.overrideWith(_NoOpRecentActivityNotifier.new),
    productsNotifierProvider.overrideWith(_EmptyProductsNotifier.new),
    posProductsProvider.overrideWith(_TestPosProductsNotifier.new),
    customerReturnsProvider.overrideWith((ref) async => []),
  ];
}

Future<void> _tapWhenReady(WidgetTester tester, Finder finder) async {
  await _waitForFinder(tester, finder);
  final button = tester.widget<FilledButton>(finder);
  expect(button.onPressed, isNotNull);
  await tester.runAsync(() async {
    button.onPressed!.call();
  });
  await tester.pump();
}

Future<void> _waitForFinder(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 24; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Missing widget: $finder');
}

Future<ProviderContainer> _pumpB38InvoiceDialog(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 5000));
  final container = ProviderContainer(overrides: overrides);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: InvoiceDetailsDialog(invoiceId: _b38UiInvoiceId),
        ),
      ),
    ),
  );
  await _pumpUntilB38InvoiceLoaded(tester);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (container.read(authProvider).valueOrNull?.user != null) {
      break;
    }
  }
  expect(container.read(authProvider).valueOrNull?.user?.id, isNotNull);
  return container;
}

Future<void> _flushInvoiceReturnUi(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pump();
}

Future<({sqlite3.Database rawDb, String path})> openSimulatedV43RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b16_v43_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
    'DROP TABLE IF EXISTS customer_invoice_return_idempotency',
  );
  await bootstrap.customStatement('PRAGMA user_version = 43');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 43);
  return (rawDb: rawDb, path: dbPath);
}

void main() {
  // Keep aligned with AppDatabase.schemaVersion (lib/core/database/app_database.dart).

  const returnedByUserId = 1;
  const unitPrice = 10.0;
  const defaultPartialQty = 2.0;

  late AppDatabase db;
  late CustomerInvoiceReturnService service;
  late int customerId;
  late int productId;
  late int saleItemId;
  late int invoiceId;

  Future<void> seedCreditInvoice({
    required AppDatabase target,
    double debtAmount = 100,
    double cashPaid = 0,
    double saleQty = 10,
    int? customerOverride,
    int? productOverride,
  }) async {
    final pid = productOverride ?? productId;
    final goodsTotal = saleQty * unitPrice;
    invoiceId = await target.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('B16-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(goodsTotal),
        total: Value(goodsTotal),
        debtAmount: Value(debtAmount),
        cashPaid: Value(cashPaid),
        customerId: customerOverride != null
            ? Value(customerOverride)
            : Value(customerId),
        paymentMethod: Value(cashPaid > 0 ? 'MIXED' : 'DEBT'),
      ),
      items: [
        {
          'productId': pid,
          'qty': saleQty,
          'price': unitPrice,
          'cost': 5.0,
        },
      ],
    );
    saleItemId =
        (await target.salesDao.getItemsForInvoice(invoiceId)).single.id;
    if (debtAmount > 0 && customerOverride != null) {
      await target.customerAccountsDao.recordSale(
        customerId: customerOverride,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'B16 credit sale',
      );
    } else if (debtAmount > 0) {
      await target.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'B16 credit sale',
      );
    }
  }

  CustomerInvoicePartialReturnLine partialLine(
    double qty, {
    int? itemId,
  }) =>
      CustomerInvoicePartialReturnLine(
        saleItemId: itemId ?? saleItemId,
        quantity: qty,
      );

  List<CustomerInvoicePartialReturnLine> defaultPartialLines([
    double qty = defaultPartialQty,
  ]) =>
      [partialLine(qty)];

  Future<int> idempotencyRowCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.customerInvoiceReturnIdempotency).get())
        .length;
  }

  Future<int> customerReturnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.customerReturns).get()).length;
  }

  Future<int> saleItemReturnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await target.select(target.saleItemReturns).get()).length;
  }

  Future<int> returnTxnCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.customerTransactions)
              ..where((t) => t.type.equals('RETURN')))
            .get())
        .length;
  }

  Future<int> returnInLedgerCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.stockLedger)
              ..where(
                (l) => l.movementType.equals(StockMovementType.returnIn.code),
              ))
            .get())
        .length;
  }

  Future<int> activityLogCount([AppDatabase? database]) async {
    final target = database ?? db;
    return (await (target.select(target.activityLogs)
              ..where(
                (l) => l.activityType.isIn([
                  ActivityTypes.returnPartial,
                  ActivityTypes.returnFull,
                ]),
              ))
            .get())
        .length;
  }

  Future<double> returnCreditTotal([AppDatabase? database]) async {
    final target = database ?? db;
    return target.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
      customerId: customerId,
      invoiceId: invoiceId,
    );
  }

  Future<double> productStock([AppDatabase? database]) async {
    final target = database ?? db;
    return target.stockDao.getStock(productId);
  }

  Future<bool> idempotencyTableExists(AppDatabase database) async {
    final rows = await database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='customer_invoice_return_idempotency'",
    ).get();
    return rows.isNotEmpty;
  }

  Future<void> seedConcurrentDatabase(AppDatabase target) async {
    customerId = await target.into(target.customers).insert(
          const CustomersCompanion(name: Value('B16 Concurrent Customer')),
        );
    productId = await target.into(target.products).insert(
          const ProductsCompanion(
            name: Value('B16 Concurrent Product'),
            barcode: Value('B16-CONCURRENT'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    await seedCreditInvoice(target: target);
  }

  Future<Object?> _tryPostPartial(
    CustomerInvoiceReturnService targetService, {
    required String idempotencyKey,
    List<CustomerInvoicePartialReturnLine>? lines,
    String? note,
  }) async {
    try {
      return await postPartialCustomerInvoiceReturn(
        targetService,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: lines ?? defaultPartialLines(),
        note: note,
        idempotencyKey: idempotencyKey,
      );
    } on CustomerInvoiceReturnIdempotencyConflictException {
      return 'conflict';
    }
  }

  Future<Object?> runPartialWithBusyRetry(
    CustomerInvoiceReturnService targetService, {
    required String idempotencyKey,
    required double quantity,
    String? note,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await postPartialCustomerInvoiceReturn(
          targetService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(quantity)],
          note: note,
          idempotencyKey: idempotencyKey,
        );
      } on CustomerInvoiceReturnIdempotencyConflictException {
        return 'conflict';
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
    throw StateError('B16 partial exhausted busy retries');
  }

  Future<Object?> runFullWithBusyRetry(
    CustomerInvoiceReturnService targetService, {
    required String idempotencyKey,
    String note = 'B16 concurrent full',
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await postFullCustomerInvoiceReturn(
          targetService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: note,
          idempotencyKey: idempotencyKey,
        );
      } on CustomerInvoiceReturnIdempotencyConflictException {
        return 'conflict';
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
    throw StateError('B16 full exhausted busy retries');
  }

  setUp(() async {
    db = AppDatabase.test();
    service = CustomerInvoiceReturnService(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('B16 Credit Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B16 Product'),
            barcode: Value('B16-PROD'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
    await seedCreditInvoice(target: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('B16 customer invoice return idempotency', () {
    test('A) first partial succeeds', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final result = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );

      expect(result.idempotentReplay, isFalse);
      expect(result.customerReturnId, greaterThan(0));
      expect(result.returnType, CustomerInvoiceReturnType.partial);
      expect(result.executionPath, CustomerInvoiceExecutionPath.partialBatch);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await saleItemReturnCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await returnInLedgerCount(), 1);
      expect(await productStock(), closeTo(92, 0.001));
      expect(await activityLogCount(), 1);
    });

    test('B) same key + same fingerprint partial replays', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final replay = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
    });

    test('C) replay returns same customerReturnId', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final second = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(second.customerReturnId, first.customerReturnId);
    });

    test('D) replay creates no second customer_returns row', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('E) replay creates no second sale_item_returns row', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await saleItemReturnCount(), 1);
    });

    test('F) replay creates no second RETURN transaction', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await returnTxnCount(), 1);
    });

    test('G) same key + different qty conflicts', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(3),
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );
    });

    test('H) conflict creates no mutation', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final creditAfterFirst = await returnCreditTotal();
      final stockAfterFirst = await productStock();

      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(4),
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );

      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
      expect(await saleItemReturnCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await returnInLedgerCount(), 1);
      expect(await returnCreditTotal(), creditAfterFirst);
      expect(await productStock(), stockAfterFirst);
    });

    test('I) sequential retry after successful commit replays', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);

      final second = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(second.idempotentReplay, isTrue);
      expect(second.customerReturnId, first.customerReturnId);
    });

    test('J) preSealHook failure then retry succeeds fresh', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final failingService = CustomerInvoiceReturnService(
        db,
        preSealHook: () async {
          throw Exception('forced preSeal failure');
        },
      );

      await expectLater(
        postPartialCustomerInvoiceReturn(
          failingService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: key,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('K) two connections same key same partial commits once', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await seedConcurrentDatabase(dbA);

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final sameKey = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait([
        postPartialCustomerInvoiceReturn(
          serviceA,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: sameKey,
        ),
        postPartialCustomerInvoiceReturn(
          serviceB,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: sameKey,
        ),
      ]);

      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.customerReturnId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('L) two connections same key different fingerprint one conflict',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_conf_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await seedConcurrentDatabase(dbA);

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final sameKey = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait<Object?>([
        _tryPostPartial(serviceA, idempotencyKey: sameKey),
        _tryPostPartial(
          serviceB,
          idempotencyKey: sameKey,
          lines: defaultPartialLines(3),
        ),
      ]);

      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.whereType<CustomerInvoiceReturnPostingResult>().length, 1);
      expect(outcomes.where((o) => o == 'conflict').length, 1);
    });

    test('M) B12 cap for different keys credits at most invoice debt', () async {
      final key1 = b16CustomerInvoiceReturnIdempotencyKey();
      final key2 = b16CustomerInvoiceReturnIdempotencyKey();

      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(6),
        idempotencyKey: key1,
      );
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(4),
        idempotencyKey: key2,
      );

      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 2);
      expect(await saleItemReturnCount(), 2);
      expect(await returnCreditTotal(), closeTo(100, 0.0001));
      expect(await returnTxnCount(), 2);
    });

    test('N) quantity cap rejects second key after full qty returned', () async {
      final capProductId = await db.into(db.products).insert(
            ProductsCompanion(
              name: const Value('B16 Cap Product'),
              barcode: Value(
                'B16-CAP-',
              ),
              currentStock: const Value(100),
              costPrice: const Value(5),
            ),
          );
      await seedCreditInvoice(
        target: db,
        productOverride: capProductId,
        saleQty: 10,
        debtAmount: 100,
      );
      final capInvoiceId = invoiceId;
      final capSaleItemId = saleItemId;

      final key1 = b16CustomerInvoiceReturnIdempotencyKey();
      final key2 = b16CustomerInvoiceReturnIdempotencyKey();

      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: capInvoiceId,
        returnedByUserId: returnedByUserId,
        lines: [partialLine(10, itemId: capSaleItemId)],
        idempotencyKey: key1,
      );

      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: capInvoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(1, itemId: capSaleItemId)],
          idempotencyKey: key2,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('O) credit poster failure rolls back return and idempotency row',
        () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final failingService = CustomerInvoiceReturnService.withCreditPoster(
        db,
        creditPoster: ({
          required int customerId,
          required double amount,
          required int returnId,
          String note = '',
        }) async {
          throw Exception('forced credit poster failure');
        },
      );
      final stockBefore = await productStock();

      await expectLater(
        postPartialCustomerInvoiceReturn(
          failingService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: key,
        ),
        throwsA(isA<Exception>()),
      );

      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await saleItemReturnCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await productStock(), stockBefore);
    });

    test('P) migration v43 -> v44 creates customer_invoice_return_idempotency',
        () async {
      final opened = await openSimulatedV43RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='customer_invoice_return_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 51);
      expect(await idempotencyTableExists(migrated), isTrue);
    });

    test('Q) seal race preSealHook then retry succeeds once', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      var hookCalls = 0;
      final flakyService = CustomerInvoiceReturnService(
        db,
        preSealHook: () async {
          hookCalls++;
          if (hookCalls == 1) {
            throw Exception('forced seal race');
          }
        },
      );

      await expectLater(
        postPartialCustomerInvoiceReturn(
          flakyService,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          idempotencyKey: key,
        ),
        throwsA(isA<Exception>()),
      );
      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);

      final retry = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('R) duplicate line ordering shares fingerprint and replays', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final unordered = [
        partialLine(2),
        partialLine(1),
      ];
      final ordered = [
        partialLine(1),
        partialLine(2),
      ];

      expect(
        CustomerInvoiceReturnFingerprint.computePartial(
          customerId: customerId,
          saleInvoiceId: invoiceId,
          lines: unordered
              .map(
                (line) => CustomerInvoicePartialReturnLineInput(
                  saleItemId: line.saleItemId,
                  quantity: line.quantity,
                ),
              )
              .toList(),
        ),
        CustomerInvoiceReturnFingerprint.computePartial(
          customerId: customerId,
          saleInvoiceId: invoiceId,
          lines: ordered
              .map(
                (line) => CustomerInvoicePartialReturnLineInput(
                  saleItemId: line.saleItemId,
                  quantity: line.quantity,
                ),
              )
              .toList(),
        ),
      );

      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: unordered,
        idempotencyKey: key,
      );
      final replay = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: ordered,
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(await customerReturnCount(), 1);
    });

    test('S) different note on same key conflicts', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        note: 'first note',
        idempotencyKey: key,
      );
      await expectLater(
        postPartialCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: defaultPartialLines(),
          note: 'second note',
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );
    });

    test('T) walk-in cash invoice null customerId idempotency works', () async {
      await seedCreditInvoice(
        target: db,
        debtAmount: 0,
        cashPaid: 100,
      );
      await (db.update(db.salesInvoices)..where((i) => i.id.equals(invoiceId)))
          .write(const SalesInvoicesCompanion(customerId: Value(null)));

      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.customerId, isNull);

      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(first.idempotentReplay, isFalse);
      expect(await returnTxnCount(), 0);

      final replay = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(await returnTxnCount(), 0);
      expect(await customerReturnCount(), 1);
    });

    test('U) independent partial keys create two returns', () async {
      final key1 = b16CustomerInvoiceReturnIdempotencyKey();
      final key2 = b16CustomerInvoiceReturnIdempotencyKey();
      expect(key1, isNot(equals(key2)));

      final first = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key1,
      );
      final second = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(1),
        idempotencyKey: key2,
      );

      expect(first.idempotentReplay, isFalse);
      expect(second.idempotentReplay, isFalse);
      expect(first.primaryReferenceId, isNot(equals(second.primaryReferenceId)));
      expect(first.customerReturnId, second.customerReturnId);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 2);
      expect(await saleItemReturnCount(), 2);
      expect(await returnTxnCount(), 2);
    });

    test('V) empty partial lines rejects before idempotency record', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await expectLater(
        service.processPartialReturn(
          idempotencyKey: key,
          saleInvoiceId: invoiceId,
          lines: const [],
          returnedByUserId: returnedByUserId,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await idempotencyRowCount(), 0);
      expect(await customerReturnCount(), 0);
    });

    test('W) partial then full different keys both succeed', () async {
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();

      final partial = await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(4),
        idempotencyKey: partialKey,
      );
      final full = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B16 partial then full',
        idempotencyKey: fullKey,
      );

      expect(partial.idempotentReplay, isFalse);
      expect(full.idempotentReplay, isFalse);
      expect(full.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      expect(await idempotencyRowCount(), 2);
      expect(await returnCreditTotal(), closeTo(100, 0.0001));
      final inv = await db.salesDao.getInvoiceById(invoiceId);
      expect(inv!.invoiceStatus, InvoiceLifecycleStatus.returned);
    });

    test('X) first fresh full succeeds fullFresh without sale_item_returns',
        () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      final result = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B16 fresh full',
        idempotencyKey: key,
      );

      expect(result.idempotentReplay, isFalse);
      expect(result.executionPath, CustomerInvoiceExecutionPath.fullFresh);
      expect(result.customerReturnId, greaterThan(0));
      expect(result.primaryReferenceId, result.customerReturnId);
      expect(await saleItemReturnCount(), 0);
      expect(await customerReturnCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await activityLogCount(), 1);
    });

    test('Y) fresh full replay keeps ids and creates no sale_item_returns',
        () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      const note = 'B16 fresh full replay';
      final first = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: key,
      );
      expect(first.executionPath, CustomerInvoiceExecutionPath.fullFresh);
      expect(await saleItemReturnCount(), 0);

      final replay = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: key,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(replay.primaryReferenceId, first.primaryReferenceId);
      expect(replay.executionPath, CustomerInvoiceExecutionPath.fullFresh);
      expect(await saleItemReturnCount(), 0);
      expect(await customerReturnCount(), 1);
    });

    test('Z) full remaining path after partial', () async {
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(3),
        idempotencyKey: partialKey,
      );

      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();
      final full = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B16 full remaining',
        idempotencyKey: fullKey,
      );

      expect(full.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      expect(full.primaryReferenceId, isNotNull);
      expect(await saleItemReturnCount(), 2);
    });

    test('AA) full remaining replay preserves sealed executionPath and refs',
        () async {
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(3),
        idempotencyKey: partialKey,
      );

      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();
      const note = 'B16 full remaining replay';
      final first = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: fullKey,
      );
      expect(first.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      final sirAfterFirst = await saleItemReturnCount();

      final replay = await postFullCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
        idempotencyKey: fullKey,
      );
      expect(replay.idempotentReplay, isTrue);
      expect(replay.customerReturnId, first.customerReturnId);
      expect(replay.primaryReferenceId, first.primaryReferenceId);
      expect(replay.executionPath, CustomerInvoiceExecutionPath.fullRemaining);
      expect(await saleItemReturnCount(), sirAfterFirst);
    });

    test('AB) activity log count unchanged on replay', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      final logsAfterFirst = await activityLogCount();

      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      expect(await activityLogCount(), logsAfterFirst);
    });

    test('AC) same key partial then full conflicts', () async {
      final key = b16CustomerInvoiceReturnIdempotencyKey();
      await postPartialCustomerInvoiceReturn(
        service,
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: defaultPartialLines(),
        idempotencyKey: key,
      );
      await expectLater(
        postFullCustomerInvoiceReturn(
          service,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: 'B16 conflict full',
          idempotencyKey: key,
        ),
        throwsA(isA<CustomerInvoiceReturnIdempotencyConflictException>()),
      );
      expect(await idempotencyRowCount(), 1);
    });

    test('AD) B13 race partial then full routes fullRemaining', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_race_${DateTime.now().microsecondsSinceEpoch}.db';
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
      await seedConcurrentDatabase(dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 5000');

      final dbB = AppDatabase.test(NativeDatabase.opened(rawB));
      await dbB.customStatement('PRAGMA busy_timeout = 5000');
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final partialKey = b16CustomerInvoiceReturnIdempotencyKey();
      final fullKey = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait<Object?>([
        runPartialWithBusyRetry(
          serviceA,
          idempotencyKey: partialKey,
          quantity: 4,
        ),
        runFullWithBusyRetry(serviceB, idempotencyKey: fullKey),
      ]);

      final fullResult = outcomes
          .whereType<CustomerInvoiceReturnPostingResult>()
          .where((r) => r.returnType == CustomerInvoiceReturnType.full)
          .toList();
      expect(fullResult, isNotEmpty);
      expect(
        fullResult.single.executionPath,
        CustomerInvoiceExecutionPath.fullRemaining,
      );
      expect(await returnCreditTotal(dbA), closeTo(100, 0.0001));
      expect(await idempotencyRowCount(dbA), 2);
    });

    test('AJ) two connections full vs full same key commits once', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_full_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await seedConcurrentDatabase(dbA);
      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final sameKey = b16CustomerInvoiceReturnIdempotencyKey();
      const note = 'B16 concurrent fresh full';

      final outcomes = await Future.wait([
        postFullCustomerInvoiceReturn(
          serviceA,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: note,
          idempotencyKey: sameKey,
        ),
        postFullCustomerInvoiceReturn(
          serviceB,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          note: note,
          idempotencyKey: sameKey,
        ),
      ]);

      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 1);
      expect(outcomes.map((r) => r.customerReturnId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
      expect(
        outcomes.singleWhere((r) => !r.idempotentReplay).executionPath,
        CustomerInvoiceExecutionPath.fullFresh,
      );
    });

    test('AK) two connections partial vs partial different keys both commit',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b16_partial_conc_${DateTime.now().microsecondsSinceEpoch}.db';
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

      await seedConcurrentDatabase(dbA);
      await dbA.customStatement('PRAGMA busy_timeout = 15000');
      await dbB.customStatement('PRAGMA busy_timeout = 15000');

      final serviceA = CustomerInvoiceReturnService(dbA);
      final serviceB = CustomerInvoiceReturnService(dbB);
      final keyA = b16CustomerInvoiceReturnIdempotencyKey();
      final keyB = b16CustomerInvoiceReturnIdempotencyKey();

      final outcomes = await Future.wait([
        postPartialCustomerInvoiceReturn(
          serviceA,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(2)],
          idempotencyKey: keyA,
        ),
        postPartialCustomerInvoiceReturn(
          serviceB,
          saleInvoiceId: invoiceId,
          returnedByUserId: returnedByUserId,
          lines: [partialLine(3)],
          idempotencyKey: keyB,
        ),
      ]);

      expect(outcomes, hasLength(2));
      expect(outcomes.every((r) => !r.idempotentReplay), isTrue);
      expect(await customerReturnCount(dbA), 1);
      expect(await idempotencyRowCount(dbA), 2);
      expect(await saleItemReturnCount(dbA), 2);
      expect(await returnCreditTotal(dbA), closeTo(50, 0.0001));
    });
  });

  group('B38 customer invoice return submit runner', () {
    test('skips second submit while in flight', () async {
      final runner = CustomerInvoiceReturnSubmitRunner();
      final gate = Completer<void>();
      const intent = CustomerInvoiceReturnSubmitIntent.full(
        saleInvoiceId: 1,
        customerId: 2,
        returnedByUserId: 1,
        note: 'note',
      );
      var calls = 0;

      final firstFuture = runner.submit(
        intent: intent,
        idempotencyKey: 'key-a',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          calls++;
          await gate.future;
          return _CountingCustomerInvoiceReturnService._stubFull;
        },
        postSuccessRefresh: (_) async {},
      );

      final second = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-a',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          calls++;
          return _CountingCustomerInvoiceReturnService._stubFull;
        },
        postSuccessRefresh: (_) async {},
      );

      expect(second, CustomerInvoiceReturnSubmitOutcome.skippedInFlight);
      gate.complete();
      await firstFuture;
      expect(calls, 1);
    });

    test('partial intent stale completion skips post-success refresh', () async {
      final runner = CustomerInvoiceReturnSubmitRunner();
      var current = true;
      var refreshCalls = 0;
      const intent = CustomerInvoiceReturnSubmitIntent.partial(
        saleInvoiceId: 3,
        customerId: 4,
        returnedByUserId: 1,
        note: 'partial',
        partialLines: [
          CustomerInvoicePartialReturnLine(saleItemId: 9, quantity: 1),
        ],
      );

      final outcome = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-stale-partial',
        isSubmitStillCurrent: () => current,
        invokeService: (_) async {
          current = false;
          return _CountingCustomerInvoiceReturnService._stubPartial;
        },
        postSuccessRefresh: (_) async {
          refreshCalls++;
        },
      );

      expect(outcome, CustomerInvoiceReturnSubmitOutcome.staleCompletion);
      expect(refreshCalls, 0);
    });

    test('full intent stale completion skips post-success refresh', () async {
      final runner = CustomerInvoiceReturnSubmitRunner();
      var current = true;
      var refreshCalls = 0;
      const intent = CustomerInvoiceReturnSubmitIntent.full(
        saleInvoiceId: 3,
        customerId: 4,
        returnedByUserId: 1,
        note: 'full stale',
      );

      final outcome = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-stale-full',
        isSubmitStillCurrent: () => current,
        invokeService: (_) async {
          current = false;
          return _CountingCustomerInvoiceReturnService._stubFull;
        },
        postSuccessRefresh: (_) async {
          refreshCalls++;
        },
      );

      expect(outcome, CustomerInvoiceReturnSubmitOutcome.staleCompletion);
      expect(refreshCalls, 0);
    });

    test('maps idempotency conflict to outcome', () async {
      final runner = CustomerInvoiceReturnSubmitRunner();
      const intent = CustomerInvoiceReturnSubmitIntent.full(
        saleInvoiceId: 1,
        customerId: 1,
        returnedByUserId: 1,
        note: 'n',
      );

      final outcome = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-conflict',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async {
          throw const CustomerInvoiceReturnIdempotencyConflictException();
        },
        postSuccessRefresh: (_) async {},
      );

      expect(outcome, CustomerInvoiceReturnSubmitOutcome.idempotencyConflict);
    });

    test('post-success refresh failure outcome', () async {
      final runner = CustomerInvoiceReturnSubmitRunner();
      const intent = CustomerInvoiceReturnSubmitIntent.full(
        saleInvoiceId: 1,
        customerId: 1,
        returnedByUserId: 1,
        note: 'n',
      );

      final outcome = await runner.submit(
        intent: intent,
        idempotencyKey: 'key-refresh',
        isSubmitStillCurrent: () => true,
        invokeService: (_) async =>
            _CountingCustomerInvoiceReturnService._stubFull,
        postSuccessRefresh: (_) async {
          throw Exception('refresh failed');
        },
      );

      expect(
        outcome,
        CustomerInvoiceReturnSubmitOutcome.postSuccessRefreshFailed,
      );
    });
  });

  group('B38 invoice return UI idempotency', () {
    late AppDatabase uiDb;
    late int uiCustomerId;
    late _CountingCustomerInvoiceReturnService spy;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      InvoiceDetailsDialog.resetInvoiceReturnTestingHooks();
      uiDb = AppDatabase.test();
      uiCustomerId = await uiDb.into(uiDb.customers).insert(
            const CustomersCompanion(name: Value('B38 UI Customer')),
          );
      await _seedB38UiInvoice(uiDb, uiCustomerId);
      InvoiceDetailsDialog.invoiceLookupDatabaseOverride = uiDb;
      spy = _CountingCustomerInvoiceReturnService(uiDb);
    });

    tearDown(() async {
      InvoiceDetailsDialog.resetInvoiceReturnTestingHooks();
      await uiDb.close();
    });

    InvoiceDetailData detail() => _b38InvoiceDetail(customerId: uiCustomerId);

    Future<void> openB38Dialog(
      WidgetTester tester,
      _CountingCustomerInvoiceReturnService activeSpy,
    ) async {
      final container = await _pumpB38InvoiceDialog(
        tester,
        overrides: _b38UiOverrides(
          detail: detail(),
          spy: activeSpy,
          user: _b38TestUser(),
        ),
      );
      addTearDown(container.dispose);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final partialBtn = find.byKey(const Key('invoice_partial_return_submit'));
        if (partialBtn.evaluate().isEmpty) continue;
        final partialButton = tester.widget<FilledButton>(partialBtn);
        if (partialButton.onPressed != null) {
          return;
        }
      }
    }

    Future<void> confirmFullReturnNote(WidgetTester tester, String note) async {
      final noteField = find.byKey(const Key('invoice_full_return_note_field'));
      await _waitForFinder(tester, noteField);
      await tester.enterText(noteField, note);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'تأكيد الإرجاع'));
      await tester.pump();
    }

    Future<void> confirmPartialReturnNote(WidgetTester tester, String note) async {
      final noteField = find.byKey(const Key('invoice_partial_return_note_field'));
      await _waitForFinder(tester, noteField);
      await tester.enterText(noteField, note);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'تأكيد'));
      await tester.pump();
    }

    Finder _partialQtyField() => find.byKey(
          Key('invoice_partial_return_qty_$_b38UiSaleItemId'),
        );

    Future<void> tapFullReturn(WidgetTester tester) async {
      await _tapWhenReady(
        tester,
        find.byKey(const Key('invoice_full_return_submit')),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find
            .byKey(const Key('invoice_full_return_note_field'))
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    }

    Future<void> tapPartialSubmit(WidgetTester tester) async {
      await _tapWhenReady(
        tester,
        find.byKey(const Key('invoice_partial_return_submit')),
      );
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (find
            .byKey(const Key('invoice_partial_return_note_field'))
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
    }

    Future<void> enterPartialQty(WidgetTester tester, String qty) async {
      final field = _partialQtyField();
      await _waitForFinder(tester, field);
      await tester.enterText(field, qty);
      await tester.pump();
    }

    testWidgets('partial duplicate submit invokes service once', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingCustomerInvoiceReturnService(uiDb, returnGate: gate);

      await openB38Dialog(tester, spy);

      await enterPartialQty(tester, '2');
      await tapPartialSubmit(tester);
      await confirmPartialReturnNote(tester, 'partial note');
      await _flushInvoiceReturnUi(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('invoice_partial_return_submit')),
            )
            .onPressed,
        isNull,
      );
      expect(spy.partialReturnCalls, 1);
      await _finishGatedInvoiceReturn(tester, gate);
    });

    testWidgets('full duplicate in-flight invokes processFullReturn once',
        (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      spy = _CountingCustomerInvoiceReturnService(uiDb, returnGate: gate);

      await openB38Dialog(tester, spy);

      await tapFullReturn(tester);
      await confirmFullReturnNote(tester, 'dup full');
      await _flushInvoiceReturnUi(tester);

      expect(spy.fullReturnCalls, 1);
      await _finishGatedInvoiceReturn(tester, gate);
    });

    testWidgets('full conflict clears key for next attempt', (tester) async {
      spy.throwConflict = true;

      await openB38Dialog(tester, spy);

      await tapFullReturn(tester);
      await confirmFullReturnNote(tester, 'conflict full');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      spy.throwConflict = false;
      await tapFullReturn(tester);
      await confirmFullReturnNote(tester, 'conflict full retry');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(spy.fullReturnCalls, 2);
      expect(spy.fullKeysUsed.length, 2);
      expect(spy.fullKeysUsed[0], isNot(spy.fullKeysUsed[1]));
    });

    testWidgets('full service failure retry reuses same key', (tester) async {
      spy.throwOnce = true;

      await openB38Dialog(tester, spy);

      await tapFullReturn(tester);
      await confirmFullReturnNote(tester, 'retry full');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      await tapFullReturn(tester);
      await confirmFullReturnNote(tester, 'retry full');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(spy.fullReturnCalls, 2);
      expect(spy.fullKeysUsed.length, 2);
      expect(spy.fullKeysUsed[0], spy.fullKeysUsed[1]);
    });

    testWidgets('partial quantities read after note dialog closes',
        (tester) async {
      await openB38Dialog(tester, spy);

      await enterPartialQty(tester, '2');
      await tapPartialSubmit(tester);

      await tester.enterText(_partialQtyField(), '4');
      await tester.pump();

      await confirmPartialReturnNote(tester, 'qty after note');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(spy.lastPartialLines?.single.quantity, 4);
    });

    testWidgets('partial success clears qty and callbacks once', (tester) async {
      await openB38Dialog(tester, spy);

      await enterPartialQty(tester, '2');
      await tapPartialSubmit(tester);
      await confirmPartialReturnNote(tester, 'success partial');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(spy.partialReturnCalls, 1);
      expect(InvoiceDetailsDialog.partialReturnPostSuccessRefreshCount, 1);
      expect(InvoiceDetailsDialog.invoicePartialReturnOnDoneCount, 1);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('partial conflict clears key for next attempt', (tester) async {
      spy.throwConflict = true;

      await openB38Dialog(tester, spy);

      await enterPartialQty(tester, '2');
      await tapPartialSubmit(tester);
      await confirmPartialReturnNote(tester, 'conflict partial');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      spy.throwConflict = false;
      await enterPartialQty(tester, '2');
      await tapPartialSubmit(tester);
      await confirmPartialReturnNote(tester, 'conflict partial retry');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(spy.partialReturnCalls, 2);
      expect(spy.partialKeysUsed.length, 2);
      expect(spy.partialKeysUsed[0], isNot(spy.partialKeysUsed[1]));
    });

    testWidgets('partial service failure retry reuses same key', (tester) async {
      spy.throwOnce = true;

      await openB38Dialog(tester, spy);

      await enterPartialQty(tester, '2');
      await tapPartialSubmit(tester);
      await confirmPartialReturnNote(tester, 'retry partial');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      await enterPartialQty(tester, '2');
      await tapPartialSubmit(tester);
      await confirmPartialReturnNote(tester, 'retry partial');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(spy.partialReturnCalls, 2);
      expect(spy.partialKeysUsed.length, 2);
      expect(spy.partialKeysUsed[0], spy.partialKeysUsed[1]);
    });

    testWidgets('post-success refresh failure shows message and retains key',
        (tester) async {
      InvoiceDetailsDialog.failNextPostSuccessRefreshForTesting = true;

      await openB38Dialog(tester, spy);

      await tapFullReturn(tester);
      await confirmFullReturnNote(tester, 'refresh fail');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(
        find.text('تم حفظ الإرجاع، لكن تعذر تحديث العرض. أعد المحاولة.'),
        findsOneWidget,
      );

      InvoiceDetailsDialog.failNextPostSuccessRefreshForTesting = false;
      await tapFullReturn(tester);
      await confirmFullReturnNote(tester, 'refresh fail retry');
      await _finishGatedInvoiceReturn(tester, Completer<void>()..complete());

      expect(spy.fullReturnCalls, 2);
      expect(spy.fullKeysUsed.length, 2);
      expect(spy.fullKeysUsed[0], spy.fullKeysUsed[1]);
    });
  });
}