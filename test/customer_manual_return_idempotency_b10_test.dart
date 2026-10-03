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
import 'package:lez_pos/core/services/manual_return_idempotency_conflict_exception.dart';
import 'package:lez_pos/core/services/manual_return_result.dart';
import 'package:lez_pos/core/services/manual_return_service.dart';
import 'package:lez_pos/core/services/pos_sale_fingerprint.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_payment_exceeds_payable_exception.dart';
import 'package:lez_pos/features/auth/providers/auth_provider.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/pos/models/cart_item.dart';
import 'package:lez_pos/features/products/models/product_model.dart';
import 'package:lez_pos/features/products/providers/products_provider.dart';
import 'package:lez_pos/features/products/repositories/products_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/returns/providers/manual_return_service_provider.dart';
import 'package:lez_pos/features/returns/providers/return_analytics_provider.dart';
import 'package:lez_pos/features/returns/repositories/return_analytics_repository.dart';
import 'package:lez_pos/features/returns/screens/customer_returns_screen.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'support/customer_manual_return_test_keys.dart';
import 'support/customer_payment_test_keys.dart';
import 'support/supplier_payment_test_keys.dart';

Future<({sqlite3.Database rawDb, String path})>
    openSimulatedV41RawDatabase() async {
  final dbPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}b10_v41_${DateTime.now().microsecondsSinceEpoch}.db';
  final bootstrapHandle = sqlite3.sqlite3.open(dbPath);
  final bootstrap = AppDatabase.test(NativeDatabase.opened(bootstrapHandle));
  await bootstrap.select(bootstrap.products).get();
  await bootstrap.customStatement(
      'DROP TABLE IF EXISTS customer_manual_return_idempotency');
  await bootstrap.customStatement('PRAGMA user_version = 41');
  await bootstrap.close();

  final rawDb = sqlite3.sqlite3.open(dbPath);
  expect(rawDb.userVersion, 41);
  return (rawDb: rawDb, path: dbPath);
}

class _CountingManualReturnService extends ManualReturnService {
  _CountingManualReturnService(
    super.db, {
    Completer<void>? manualReturnGate,
    this.deferToSuper = true,
  }) : _manualReturnGate = manualReturnGate;

  final Completer<void>? _manualReturnGate;
  bool throwConflict = false;
  bool deferToSuper;
  int processManualReturnCalls = 0;
  final List<String> keysUsed = [];

  @override
  Future<ManualReturnResult> processManualReturn({
    required String idempotencyKey,
    required int productId,
    required double quantity,
    required double unitPrice,
    required String reason,
    int? userId,
    int? approvedByUserId,
    Future<void> Function()? preSealHook,
  }) async {
    processManualReturnCalls++;
    keysUsed.add(idempotencyKey);
    if (throwConflict) {
      throw const ManualReturnIdempotencyConflictException();
    }
    if (_manualReturnGate != null) {
      await _manualReturnGate!.future;
    }
    if (!deferToSuper) {
      return const ManualReturnResult(
        customerReturnId: 1,
        idempotentReplay: false,
      );
    }
    return super.processManualReturn(
      idempotencyKey: idempotencyKey,
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      reason: reason,
      userId: userId,
      approvedByUserId: approvedByUserId,
      preSealHook: preSealHook,
    );
  }
}

class _TestProductsNotifier extends ProductsNotifier {
  _TestProductsNotifier(this._products);

  final List<ProductModel> _products;

  @override
  Future<List<ProductModel>> build() async => _products;
}

class _FakeProductsRepository extends ProductsRepository {
  _FakeProductsRepository(super.db, this._products);

  final List<ProductModel> _products;

  @override
  Future<List<ProductModel>> getAll() async => _products;
}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._user);

  final User _user;

  @override
  FutureOr<AuthState> build() async => AuthState(user: _user);
}

class _NoOpRecentActivityNotifier extends RecentActivityNotifier {
  @override
  RecentActivityState build() => RecentActivityState.empty;

  @override
  Future<void> refresh() async {}
}

User _testUser({double refundLimit = 10000}) => User(
      id: 1,
      fullName: 'Cashier',
      username: 'cashier',
      passwordHash: 'hash',
      roleId: 1,
      isActive: true,
      refundLimit: refundLimit,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  const userId = 1;
  const sellPrice = 10.0;
  const initialStock = 100.0;
  const defaultReason = 'سبب الإرجاع';
  const unitPrice = 0.0;

  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  group('B10 customer manual return idempotency', () {
    late AppDatabase db;
    late ManualReturnService manualReturnService;
    late int productId;

    Future<int> customerReturnCount() async =>
        (await db.select(db.customerReturns).get()).length;

    Future<int> returnItemCount() async =>
        (await db.select(db.customerReturnItems).get()).length;

    Future<int> auditLogCount() async =>
        (await db.select(db.returnAuditLogs).get()).length;

    Future<int> manualReturnLogCount() async {
      final rows = await (db.select(db.logsTable)
            ..where((l) => l.actionType.equals('RETURN_WITHOUT_INVOICE')))
          .get();
      return rows.length;
    }

    Future<int> allLogsCount() async =>
        (await db.select(db.logsTable).get()).length;

    Future<int> idempotencyRowCount([AppDatabase? database]) async {
      final target = database ?? db;
      return (await target.select(target.customerManualReturnIdempotency).get())
          .length;
    }

    Future<double> stockLevel() async => db.stockDao.getStock(productId);

    Future<int> returnRefundLedgerCount([AppDatabase? database]) async {
      final target = database ?? db;
      final page =
          await FinancialLedgerRepository(target).getEntries(ledgerFilter);
      return page.entries
          .where((e) => e.eventType == CashLedgerEventType.returnRefund)
          .length;
    }

    Future<bool> idempotencyTableExists(AppDatabase database) async {
      final rows = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='customer_manual_return_idempotency'",
          )
          .get();
      return rows.isNotEmpty;
    }

    Future<ManualReturnResult> manualReturn({
      required String idempotencyKey,
      double quantity = 1,
      double unitPriceArg = unitPrice,
      String reason = defaultReason,
      int? overrideProductId,
      int? overrideUserId,
      int? approvedByUserId,
      Future<void> Function()? preSealHook,
    }) {
      return manualReturnService.processManualReturn(
        idempotencyKey: idempotencyKey,
        productId: overrideProductId ?? productId,
        quantity: quantity,
        unitPrice: unitPriceArg,
        reason: reason,
        userId: overrideUserId ?? userId,
        approvedByUserId: approvedByUserId,
        preSealHook: preSealHook,
      );
    }

    setUp(() async {
      db = AppDatabase.test();
      manualReturnService = ManualReturnService(db);

      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('B10 Manual Return Product'),
              barcode: Value('B10-MR-1'),
              currentStock: Value(initialStock),
              costPrice: Value(5),
              sellPrice: Value(sellPrice),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('1) first manual return succeeds', () async {
      final key = b10ManualReturnIdempotencyKey();
      final result = await manualReturn(idempotencyKey: key);

      expect(result.idempotentReplay, isFalse);
      expect(result.customerReturnId, greaterThan(0));
      expect(await customerReturnCount(), 1);
      expect(await stockLevel(), initialStock + 1);
    });

    test('2) same key + same fingerprint replays', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key);
      final replay = await manualReturn(idempotencyKey: key);
      expect(replay.idempotentReplay, isTrue);
    });

    test('3) replay returns same customerReturnId', () async {
      final key = b10ManualReturnIdempotencyKey();
      final first = await manualReturn(idempotencyKey: key);
      final replay = await manualReturn(idempotencyKey: key);
      expect(replay.customerReturnId, first.customerReturnId);
    });

    test('4) replay does not increase stock again', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key, quantity: 2);
      final stockAfterFirst = await stockLevel();
      await manualReturn(idempotencyKey: key, quantity: 2);
      expect(await stockLevel(), stockAfterFirst);
    });

    test('5) replay creates no second customer_returns row', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key);
      await manualReturn(idempotencyKey: key);
      expect(await customerReturnCount(), 1);
    });

    test('6) replay creates no second customer_return_items row', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key);
      await manualReturn(idempotencyKey: key);
      expect(await returnItemCount(), 1);
    });

    test('7) replay creates no second return_audit_logs row', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key);
      await manualReturn(idempotencyKey: key);
      expect(await auditLogCount(), 1);
    });

    test('8) replay creates no logsTable row', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key);
      await manualReturn(idempotencyKey: key);
      expect(await manualReturnLogCount(), 0);
      expect(await allLogsCount(), 0);
    });

    test('9) manual return creates NO logsTable row', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key);
      expect(await manualReturnLogCount(), 0);
      expect(await allLogsCount(), 0);
    });

    test('10) changed product + same key conflicts', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key);
      final otherProductId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Other Product'),
              barcode: Value('B10-MR-2'),
              currentStock: Value(50),
              costPrice: Value(3),
              sellPrice: Value(8),
            ),
          );
      await expectLater(
        manualReturn(
          idempotencyKey: key,
          overrideProductId: otherProductId,
        ),
        throwsA(isA<ManualReturnIdempotencyConflictException>()),
      );
      expect(await customerReturnCount(), 1);
    });

    test('11) changed quantity + same key conflicts', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key, quantity: 1);
      await expectLater(
        manualReturn(idempotencyKey: key, quantity: 2),
        throwsA(isA<ManualReturnIdempotencyConflictException>()),
      );
    });

    test('12) changed unitPrice + same key conflicts', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key, unitPriceArg: 0);
      await expectLater(
        manualReturn(idempotencyKey: key, unitPriceArg: sellPrice),
        throwsA(isA<ManualReturnIdempotencyConflictException>()),
      );
    });

    test('13) changed reason + same key conflicts', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(idempotencyKey: key, reason: defaultReason);
      await expectLater(
        manualReturn(idempotencyKey: key, reason: 'عيب في المنتج'),
        throwsA(isA<ManualReturnIdempotencyConflictException>()),
      );
    });

    test('14) different keys create two legitimate returns', () async {
      await manualReturn(idempotencyKey: b10ManualReturnIdempotencyKey());
      await manualReturn(idempotencyKey: b10ManualReturnIdempotencyKey());
      expect(await customerReturnCount(), 2);
      expect(await idempotencyRowCount(), 2);
      expect(await stockLevel(), initialStock + 2);
    });

    test('15) validation qty<=0 creates no rows', () async {
      final key = b10ManualReturnIdempotencyKey();
      await expectLater(
        manualReturn(idempotencyKey: key, quantity: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await stockLevel(), initialStock);
    });

    test('16) missing product creates no rows', () async {
      final key = b10ManualReturnIdempotencyKey();
      await expectLater(
        manualReturn(idempotencyKey: key, overrideProductId: 99999),
        throwsA(isA<StateError>()),
      );
      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);
    });

    test('17) preSealHook failure rolls back completely', () async {
      final key = b10ManualReturnIdempotencyKey();
      await expectLater(
        manualReturn(
          idempotencyKey: key,
          preSealHook: () async {
            throw Exception('forced seal failure');
          },
        ),
        throwsA(isA<Exception>()),
      );
      expect(await customerReturnCount(), 0);
      expect(await idempotencyRowCount(), 0);
      expect(await auditLogCount(), 0);
      expect(await manualReturnLogCount(), 0);
      expect(await stockLevel(), initialStock);
    });

    test('18) retry same key after failure succeeds once', () async {
      final key = b10ManualReturnIdempotencyKey();
      await expectLater(
        manualReturn(
          idempotencyKey: key,
          preSealHook: () async {
            throw Exception('forced seal failure');
          },
        ),
        throwsA(isA<Exception>()),
      );

      final retry = await manualReturn(idempotencyKey: key);
      expect(retry.idempotentReplay, isFalse);
      expect(await customerReturnCount(), 1);
      expect(await idempotencyRowCount(), 1);
    });

    test('19) dual-connection seal race commits exactly once', () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b10_race_${DateTime.now().microsecondsSinceEpoch}.db';
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
              name: Value('Race Product'),
              barcode: Value('B10-RACE'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      final serviceA = ManualReturnService(dbA);
      final serviceB = ManualReturnService(dbB);
      final sameKey = b10ManualReturnIdempotencyKey();

      final outcomes = await Future.wait([
        serviceA.processManualReturn(
          idempotencyKey: sameKey,
          productId: pid,
          quantity: 1,
          unitPrice: unitPrice,
          reason: defaultReason,
          userId: userId,
        ),
        serviceB.processManualReturn(
          idempotencyKey: sameKey,
          productId: pid,
          quantity: 1,
          unitPrice: unitPrice,
          reason: defaultReason,
          userId: userId,
        ),
      ]);

      expect(await dbA.select(dbA.customerReturns).get(), hasLength(1));
      expect(await idempotencyRowCount(dbA), 1);
      expect(await dbA.select(dbA.returnAuditLogs).get(), hasLength(1));
      expect(
        await (dbA.select(dbA.logsTable)
              ..where((l) => l.actionType.equals('RETURN_WITHOUT_INVOICE')))
            .get(),
        isEmpty,
      );
      final stockRow = await (dbA.select(dbA.products)
            ..where((p) => p.id.equals(pid)))
          .getSingle();
      expect(stockRow.currentStock, 101);
      expect(outcomes.map((r) => r.customerReturnId).toSet().length, 1);
      expect(outcomes.where((r) => r.idempotentReplay).length, 1);
      expect(outcomes.where((r) => !r.idempotentReplay).length, 1);
    });

    test('20) SQLITE_BUSY retry succeeds under dual connection contention',
        () async {
      final dbPath =
          '${Directory.systemTemp.path}${Platform.pathSeparator}b10_busy_${DateTime.now().microsecondsSinceEpoch}.db';
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
              barcode: Value('B10-BUSY'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );

      final sameKey = b10ManualReturnIdempotencyKey();
      final results = await Future.wait([
        ManualReturnService(dbA).processManualReturn(
          idempotencyKey: sameKey,
          productId: pid,
          quantity: 1,
          unitPrice: unitPrice,
          reason: defaultReason,
          userId: userId,
        ),
        ManualReturnService(dbB).processManualReturn(
          idempotencyKey: sameKey,
          productId: pid,
          quantity: 1,
          unitPrice: unitPrice,
          reason: defaultReason,
          userId: userId,
        ),
      ]);

      expect(results.map((r) => r.customerReturnId).toSet().length, 1);
      expect(await dbA.select(dbA.customerReturns).get(), hasLength(1));
    });

    test('21) migration v41 -> v42 creates table', () async {
      final opened = await openSimulatedV41RawDatabase();
      addTearDown(opened.rawDb.dispose);

      final before = opened.rawDb.select(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='customer_manual_return_idempotency'",
      );
      expect(before, isEmpty);

      final migrated = AppDatabase.test(NativeDatabase.opened(opened.rawDb));
      addTearDown(() async => migrated.close());

      expect(migrated.schemaVersion, 42);
      expect(await idempotencyTableExists(migrated), isTrue);
    });

    test('22) fresh v42 schema includes table', () async {
      expect(db.schemaVersion, 42);
      expect(await idempotencyTableExists(db), isTrue);
    });

    test('29) B2-B9 regression sentinel on v42', () async {
      final regressionDb = AppDatabase.test();
      addTearDown(() async => regressionDb.close());
      expect(regressionDb.schemaVersion, 42);

      final b10Table = await regressionDb
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='customer_manual_return_idempotency'",
          )
          .get();
      expect(b10Table, isNotEmpty);

      final b9Table = await regressionDb
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name='customer_quick_return_idempotency'",
          )
          .get();
      expect(b9Table, isNotEmpty);

      final b4Index = await regressionDb
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND name='uq_sales_invoices_invoice_number'",
          )
          .get();
      expect(b4Index, isNotEmpty);

      final b5ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B10 Regression Product'),
              barcode: Value('B10-REG-PROD'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
      final b5CustomerId =
          await regressionDb.into(regressionDb.customers).insert(
                const CustomersCompanion(
                  name: Value('B10 Regression Customer'),
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
        name: 'B10 Regression Product',
        barcode: 'B10-REG-PROD',
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

      final b6CustomerId =
          await regressionDb.into(regressionDb.customers).insert(
                const CustomersCompanion(name: Value('B10 Regression Payer')),
              );
      final b6ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B10 Regression Pay Product'),
              barcode: Value('B10-REG-PAY'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      final b6InvoiceId = await regressionDb.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber:
              Value('B10-REG-${DateTime.now().microsecondsSinceEpoch}'),
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
        note: 'B10 regression seed debt',
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

      final b3SupplierId = await regressionDb
          .into(regressionDb.suppliers)
          .insert(
            const SuppliersCompanion(name: Value('B10 Regression Supplier')),
          );
      final b3ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B10 Regression Supplier Part'),
            ),
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

      final b2CustomerId =
          await regressionDb.into(regressionDb.customers).insert(
                const CustomersCompanion(
                  name: Value('B10 Regression Credit Customer'),
                  creditLimit: Value(100),
                ),
              );
      final b2ProductId = await regressionDb.into(regressionDb.products).insert(
            const ProductsCompanion(
              name: Value('B10 Regression Credit Product'),
              barcode: Value('B10-REG-CREDIT'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      await expectLater(
        PosSaleService(regressionDb).processSale(
          idempotencyKey: b6PaymentIdempotencyKey(),
          fingerprintHash: 'b10-b2-regression-credit-fingerprint',
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

    test('30) replay creates no second RETURN_REFUND ledger event', () async {
      final key = b10ManualReturnIdempotencyKey();
      await manualReturn(
        idempotencyKey: key,
        unitPriceArg: sellPrice,
      );
      final ledgerAfterFirst = await returnRefundLedgerCount();
      await manualReturn(
        idempotencyKey: key,
        unitPriceArg: sellPrice,
      );
      expect(await returnRefundLedgerCount(), ledgerAfterFirst);
      expect(ledgerAfterFirst, 1);
    });
  });

  group('B10 customer manual return UI lifecycle', () {
    late AppDatabase uiDb;
    late int uiProductId;

    setUp(() async {
      uiDb = AppDatabase.test();
      uiProductId = await uiDb.into(uiDb.products).insert(
            const ProductsCompanion(
              name: Value('B10 UI Product'),
              barcode: Value('B10-UI-PROD'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
    });

    tearDown(() async {
      await uiDb.close();
    });

    Future<void> pumpManualReturnScreen(
      WidgetTester tester, {
      required _CountingManualReturnService spyService,
      required List<ProductModel> products,
      required User user,
    }) async {
      final container = ProviderContainer(
        overrides: [
          manualReturnServiceProvider.overrideWithValue(spyService),
          authProvider.overrideWith(() => _TestAuthNotifier(user)),
          customerReturnsProvider.overrideWith((ref) async => []),
          productsNotifierProvider
              .overrideWith(() => _TestProductsNotifier(products)),
          productsRepositoryProvider.overrideWithValue(
            _FakeProductsRepository(spyService.db, products),
          ),
          returnAnalyticsRepositoryProvider.overrideWithValue(
            ReturnAnalyticsRepository(spyService.db),
          ),
          recentActivityProvider.overrideWith(_NoOpRecentActivityNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: CustomerReturnsScreen()),
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
        if (container.read(authProvider).valueOrNull?.user != null) {
          break;
        }
      }
      expect(container.read(authProvider).valueOrNull?.user, isNotNull);
    }

    Future<void> pumpUntilManualReturnDialog(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
        if (find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.text('مرتجع عميل جديد'),
            )
            .evaluate()
            .isNotEmpty) {
          return;
        }
      }
      fail('Manual return dialog did not load');
    }

    Future<void> openManualReturnDialog(WidgetTester tester) async {
      await tester.tap(find.text('مرتجع جديد'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await pumpUntilManualReturnDialog(tester);
    }

    Future<void> fillManualReturnDialog(WidgetTester tester) async {
      final dialog = find.byType(AlertDialog);
      await tester.tap(find.descendant(
        of: dialog,
        matching: find.text('اختر منتجاً'),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('B10 UI Product').last);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(
        find
            .descendant(
              of: dialog,
              matching: find.widgetWithText(TextField, ''),
            )
            .first,
        defaultReason,
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> drainUi(WidgetTester tester, {int frames = 10}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }
    }

    Future<void> submitManualReturnDialog(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'حفظ المرتجع'));
      await drainUi(tester);
    }

    testWidgets('23) opening new dialog clears previous pending key',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final spyService = _CountingManualReturnService(
        uiDb,
        deferToSuper: false,
      );

      await pumpManualReturnScreen(
        tester,
        spyService: spyService,
        products: [
          ProductModel(
            id: uiProductId,
            name: 'B10 UI Product',
            barcode: 'B10-UI-1',
            costPrice: 5,
            sellPrice: 10,
          ),
        ],
        user: _testUser(),
      );
      await openManualReturnDialog(tester);
      await tester.tap(find.text('إلغاء'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }

      await openManualReturnDialog(tester);
      await fillManualReturnDialog(tester);
      await submitManualReturnDialog(tester);

      expect(spyService.processManualReturnCalls, 1);
      expect(spyService.keysUsed, hasLength(1));
    });

    testWidgets('24) UI double-submit invokes processManualReturn once',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final spyService =
          _CountingManualReturnService(uiDb, deferToSuper: false);

      await pumpManualReturnScreen(
        tester,
        spyService: spyService,
        products: [
          ProductModel(
            id: uiProductId,
            name: 'B10 UI Product',
            barcode: 'B10-UI-2',
            costPrice: 5,
            sellPrice: 10,
          ),
        ],
        user: _testUser(),
      );
      await openManualReturnDialog(tester);
      await fillManualReturnDialog(tester);
      final submitButton = find.widgetWithText(ElevatedButton, 'حفظ المرتجع');
      await tester.tap(submitButton);
      await tester.pump();
      await tester.tap(submitButton, warnIfMissed: false);
      await drainUi(tester);
      expect(spyService.processManualReturnCalls, 1);
    });

    test('25) retry same key after preSealHook failure succeeds once',
        () async {
      final key = b10ManualReturnIdempotencyKey();
      final service = ManualReturnService(uiDb);

      await expectLater(
        service.processManualReturn(
          idempotencyKey: key,
          productId: uiProductId,
          quantity: 1,
          unitPrice: unitPrice,
          reason: defaultReason,
          userId: userId,
          preSealHook: () async {
            throw Exception('ordinary failure');
          },
        ),
        throwsA(isA<Exception>()),
      );

      final retry = await service.processManualReturn(
        idempotencyKey: key,
        productId: uiProductId,
        quantity: 1,
        unitPrice: unitPrice,
        reason: defaultReason,
        userId: userId,
      );
      expect(retry.idempotentReplay, isFalse);
      expect(await uiDb.select(uiDb.customerReturns).get(), hasLength(1));
    });

    testWidgets('26) UI success clears key for next dialog submit',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final spyService =
          _CountingManualReturnService(uiDb, deferToSuper: false);

      await pumpManualReturnScreen(
        tester,
        spyService: spyService,
        products: [
          ProductModel(
            id: uiProductId,
            name: 'B10 UI Product',
            barcode: 'B10-UI-3',
            costPrice: 5,
            sellPrice: 10,
          ),
        ],
        user: _testUser(),
      );
      await openManualReturnDialog(tester);
      await fillManualReturnDialog(tester);
      await submitManualReturnDialog(tester);

      await openManualReturnDialog(tester);
      await fillManualReturnDialog(tester);
      await submitManualReturnDialog(tester);

      expect(spyService.keysUsed.length, 2);
      expect(spyService.keysUsed[0], isNot(spyService.keysUsed[1]));
    });

    testWidgets('27) UI conflict clears key for next attempt', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final spyService = _CountingManualReturnService(
        uiDb,
        deferToSuper: false,
      )..throwConflict = true;

      await pumpManualReturnScreen(
        tester,
        spyService: spyService,
        products: [
          ProductModel(
            id: uiProductId,
            name: 'B10 UI Product',
            barcode: 'B10-UI-4',
            costPrice: 5,
            sellPrice: 10,
          ),
        ],
        user: _testUser(),
      );
      await openManualReturnDialog(tester);
      await fillManualReturnDialog(tester);
      await submitManualReturnDialog(tester);

      spyService.throwConflict = false;
      await openManualReturnDialog(tester);
      await fillManualReturnDialog(tester);
      await submitManualReturnDialog(tester);

      expect(spyService.keysUsed.length, 2);
      expect(spyService.keysUsed[0], isNot(spyService.keysUsed[1]));
    });

    test('28) changed user + same key conflicts', () async {
      final key = b10ManualReturnIdempotencyKey();
      final service = ManualReturnService(uiDb);
      await service.processManualReturn(
        idempotencyKey: key,
        productId: uiProductId,
        quantity: 1,
        unitPrice: unitPrice,
        reason: defaultReason,
        userId: 1,
      );
      await expectLater(
        service.processManualReturn(
          idempotencyKey: key,
          productId: uiProductId,
          quantity: 1,
          unitPrice: unitPrice,
          reason: defaultReason,
          userId: 2,
        ),
        throwsA(isA<ManualReturnIdempotencyConflictException>()),
      );
    });
  });
}
