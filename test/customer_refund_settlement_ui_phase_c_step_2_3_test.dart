import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';

import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';

import 'package:lez_pos/features/customers/providers/customer_refund_settlement_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_accounts_provider.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/customers/screens/widgets/customer_credit_refund_entry.dart';
import 'package:lez_pos/features/customers/utils/customer_refund_settlement_messages.dart';

void main() {
  group('Phase C Step 2.3 customer refund UI foundation', () {
    late AppDatabase db;
    late int customerId;
    late int productId;
    late int invoiceId;

    Future<void> seedCredit({double credit = 20}) async {
      invoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('UI-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: const Value(50),
          total: const Value(50),
          debtAmount: const Value(50),
          customerId: Value(customerId),
          paymentMethod: const Value('DEBT'),
        ),
        items: [
          {'productId': productId, 'qty': 10.0, 'price': 5.0, 'cost': 5.0},
        ],
      );
      await db.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: 50,
        invoiceId: invoiceId,
        note: 'test sale',
      );
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 50 + credit,
        note: 'overpayment',
      );
    }

    setUp(() async {
      db = AppDatabase.test();
      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Profile Customer')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
                name: Value('UI Product'),
                currentStock: Value(100),
                costPrice: Value(5)),
          );
    });

    tearDown(() async => db.close());

    ProviderContainer containerWithService(
      CustomerRefundSettlementService service,
    ) {
      return ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider.overrideWithValue(service),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
    }

    Finder refundButtonFinder() =>
        find.widgetWithText(ElevatedButton, 'استرداد من العميل');

    test('A) customer profile shows available credit', () async {
      await seedCredit(credit: 15);
      final container = ProviderContainer(
        overrides: [
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final credit = await container
          .read(customerAvailableCreditProvider(customerId).future);
      expect(credit, closeTo(15, 0.001));
    });

    testWidgets('C) positive credit enables refund entry', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => 30),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CustomerCreditRefundEntry(
                  customerId: customerId,
                  customerName: 'Profile Customer',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('الرصيد الدائن'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
          isNotNull);
    });

    testWidgets('B) zero credit disables refund entry', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => 0),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: CustomerCreditRefundEntry(
                  customerId: customerId,
                  customerName: 'Profile Customer',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('لا يوجد رصيد دائن متاح لهذا العميل'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
          isNull);
    });

    test('D) opening profile entry causes zero financial writes', () async {
      await seedCredit(credit: 20);
      final container = ProviderContainer(
        overrides: [
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final beforeRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      await container.read(customerAvailableCreditProvider(customerId).future);
      final afterRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds);
    });
    test('E) opening dialog causes zero financial writes', () async {
      await seedCredit(credit: 20);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final beforeRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      container.read(customerRefundSettlementProvider.notifier).init(
            customerId: customerId,
            customerName: 'Profile Customer',
            availableCredit: 20,
          );
      container
          .read(customerRefundSettlementProvider.notifier)
          .setAmountText('9');
      final afterRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds);
    });

    test('F) valid full refund calls the canonical settlement service',
        () async {
      await seedCredit(credit: 20);
      var callCount = 0;
      final service = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          callCount++;
          await db.customerAccountsDao.recordRefundInTransaction(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('20');
      expect(await notifier.submit(), isTrue);
      expect(callCount, 1);
    });

    test('G) valid partial refund calls the canonical settlement service',
        () async {
      await seedCredit(credit: 20);
      final container =
          containerWithService(CustomerRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('12');
      expect(await notifier.submit(), isTrue);
      expect(
        container.read(customerRefundSettlementProvider)!.status,
        CustomerRefundSettlementUiStatus.success,
      );
    });

    test('N) successful settlement refreshes credit and history', () async {
      await seedCredit(credit: 50);
      final container =
          containerWithService(CustomerRefundSettlementService(db));
      addTearDown(container.dispose);
      final before = await container
          .read(customerAvailableCreditProvider(customerId).future);
      expect(before, closeTo(50, 0.001));
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: before,
      );
      notifier.setAmountText('30');
      expect(await notifier.submit(), isTrue);
      container.invalidate(customerAvailableCreditProvider(customerId));
      container.invalidate(customerHistoryProvider(customerId));
      final after = await container
          .read(customerAvailableCreditProvider(customerId).future);
      expect(after, closeTo(20, 0.001));
      final history =
          await container.read(customerHistoryProvider(customerId).future);
      expect(history.any((row) => row.type == 'REFUND'), isTrue);
    });

    test('O) failure preserves dialog draft', () async {
      await seedCredit(credit: 20);
      final service = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          throw const CustomerRefundSettlementException(
            CustomerRefundSettlementFailure.amountExceedsCredit,
            'settlement exceeds available credit',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('10');
      notifier.setNote('profile note');
      expect(await notifier.submit(), isFalse);
      final state = container.read(customerRefundSettlementProvider)!;
      expect(state.amountText, '10');
      expect(state.note, 'profile note');
      expect(state.errorMessage, isNotNull);
      expect(state.status, CustomerRefundSettlementUiStatus.failure);
    });

    test('H) second concurrent submit is ignored', () async {
      await seedCredit(credit: 20);
      final gate = Completer<void>();
      final entered = Completer<void>();
      var callCount = 0;
      final service = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          callCount++;
          if (!entered.isCompleted) entered.complete();
          await gate.future;
          await db.customerAccountsDao.recordRefundInTransaction(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('10');
      final first = notifier.submit();
      await entered.future;
      final second = notifier.submit();
      expect(callCount, 1);
      expect(await second, isFalse);
      gate.complete();
      expect(await first, isTrue);
    });

    test('M) return-not-found and mismatch failures are mapped correctly', () {
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.returnNotFound,
        ),
        'مرتجع العميل غير موجود',
      );
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.returnCustomerMismatch,
        ),
        'المرتجع لا ينتمي إلى هذا العميل',
      );
      for (final code in CustomerRefundSettlementFailure.values) {
        final message = customerRefundSettlementFailureMessage(code);
        expect(message, isNot(contains('Exception')));
        expect(message, isNot(contains('failed')));
        expect(message, isNot(contains('stack')));
      }
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.noCustomerCredit,
        ),
        'لا يوجد رصيد دائن متاح لهذا العميل',
      );
    });

    test('P) UI settlement goes through service not direct DAO writes',
        () async {
      await seedCredit(credit: 20);
      var serviceCalls = 0;
      final service = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          serviceCalls++;
          await db.customerAccountsDao.recordRefundInTransaction(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final beforeRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('7');
      expect(await notifier.submit(), isTrue);
      expect(serviceCalls, 1);
      final afterRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds + 1);
    });

    test('Q) UI does not write Cash Ledger directly', () async {
      await seedCredit(credit: 20);
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final ledger = FinancialLedgerRepository(db);
      final before = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .length;
      final container =
          containerWithService(CustomerRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('6');
      expect(await notifier.submit(), isTrue);
      final after = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .length;
      expect(after, before + 1);
    });

    test('I) invalid amount does not call the settlement service', () async {
      await seedCredit(credit: 20);
      var callCount = 0;
      final service = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          callCount++;
        },
      );
      final container = containerWithService(service);
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('0');
      expect(await notifier.submit(), isFalse);
      expect(callCount, 0);
    });

    test('J) no-credit failure is mapped to Arabic', () {
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.noCustomerCredit,
        ),
        'لا يوجد رصيد دائن متاح لهذا العميل',
      );
    });

    test('K) amount-exceeds-credit failure is mapped to Arabic', () {
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.amountExceedsCredit,
        ),
        'مبلغ الاسترداد يتجاوز الرصيد الدائن المتاح',
      );
    });

    test('L) customer-not-found failure is mapped to Arabic', () {
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.customerNotFound,
        ),
        'العميل غير موجود',
      );
    });

    test('R) successful refund produces derived CUSTOMER_REFUND ledger event',
        () async {
      await seedCredit(credit: 20);
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final ledger = FinancialLedgerRepository(db);
      final container =
          containerWithService(CustomerRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Profile Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('8');
      expect(await notifier.submit(), isTrue);
      final events = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .toList();
      expect(events, isNotEmpty);
      expect(events.last.amount, closeTo(8, 0.001));
      expect(events.last.direction.code, 'outflow');
    });
  });
}
