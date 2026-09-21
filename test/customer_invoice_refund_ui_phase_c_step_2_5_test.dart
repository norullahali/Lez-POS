import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/invoice_lifecycle.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/auth/permissions/permission_keys.dart';
import 'package:lez_pos/features/auth/providers/permission_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_accounts_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_refund_settlement_provider.dart';
import 'package:lez_pos/features/customers/screens/widgets/customer_credit_refund_entry.dart';
import 'package:lez_pos/features/customers/utils/customer_refund_settlement_messages.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/invoices/models/invoice_detail.dart';
import 'package:lez_pos/features/invoices/providers/invoice_history_provider.dart';
import 'package:lez_pos/features/invoices/widgets/invoice_details_dialog.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/returns/providers/partial_return_provider.dart';

void main() {
  group('Phase C Step 2.5 invoice details customer refund entry', () {
    late AppDatabase db;
    late int customerId;
    late int productId;
    late int invoiceId;

    InvoiceDetailData buildDetail({
      required int id,
      int? detailCustomerId,
      required String customerName,
      String invoiceStatus = InvoiceLifecycleStatus.completed,
    }) {
      return InvoiceDetailData(
        header: InvoiceDetailHeader(
          id: id,
          invoiceNumber: 'INV-STEP-2-5',
          saleDate: DateTime(2026, 1, 15, 10, 30),
          customerId: detailCustomerId,
          customerName: customerName,
          cashierName: 'Cashier',
          paymentMethod: 'DEBT',
          invoiceStatus: invoiceStatus,
          subtotal: 50,
          discountTotal: 0,
          total: 50,
          cashPaid: 0,
          cardPaid: 0,
          changeAmount: 0,
        ),
        lines: const [
          InvoiceDetailLine(
            id: 1,
            productId: 1,
            productName: 'Test Product',
            quantity: 10,
            unitPrice: 5,
            discount: 0,
            lineTotal: 50,
          ),
        ],
        showTax: false,
      );
    }

    Future<void> seedCredit({double credit = 20}) async {
      invoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('INV-${DateTime.now().microsecondsSinceEpoch}'),
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
            const CustomersCompanion(name: Value('Invoice Customer')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Test Product'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
          );
      invoiceId = 9001;
    });

    tearDown(() async => db.close());

    Finder refundButtonFinder() =>
        find.widgetWithText(ElevatedButton, 'استرداد من العميل');

    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      int maxAttempts = 40,
    }) async {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester.any(finder)) return;
      }
      fail('Timed out waiting for $finder');
    }

    List<Override> baseOverrides({
      required InvoiceDetailData detail,
      CustomerRefundSettlementService? service,
      double? creditOverride,
    }) {
      return [
        invoiceDetailProvider(invoiceId).overrideWith((ref) async => detail),
        invoicePartialReturnQtysProvider(invoiceId)
            .overrideWith((ref) async => <int, double>{}),
        partialReturnServiceProvider
            .overrideWith((ref) => PartialReturnService(db)),
        customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        permissionProvider(PermissionKeys.posFullRefund)
            .overrideWith((ref) => true),
        if (service != null)
          customerRefundSettlementServiceProvider.overrideWithValue(service),
        if (creditOverride != null)
          customerAvailableCreditProvider(detail.header.customerId!)
              .overrideWith((ref) async => creditOverride),
      ];
    }

    testWidgets('A) invoice details loads normally without financial writes',
        (tester) async {
      late InvoiceDetailData detail;
      var beforeRefunds = 0;

      await tester.runAsync(() async {
        await seedCredit();
        detail = buildDetail(
          id: invoiceId,
          detailCustomerId: customerId,
          customerName: 'Invoice Customer',
        );
        beforeRefunds = (await (db.select(db.customerTransactions)
                  ..where((t) => t.type.equals('REFUND')))
                .get())
            .length;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(
            detail: detail,
            creditOverride: 20,
          ),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      await pumpUntilFound(
          tester, find.textContaining('تفاصيل الفاتورة INV-STEP-2-5'));
      expect(find.text('الإرجاع الجزئي'), findsOneWidget);

      var afterRefunds = 0;
      await tester.runAsync(() async {
        afterRefunds = (await (db.select(db.customerTransactions)
                  ..where((t) => t.type.equals('REFUND')))
                .get())
            .length;
      });
      expect(afterRefunds, beforeRefunds);
    });

    testWidgets('B) eligible customer with positive credit shows refund entry',
        (tester) async {
      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(detail: detail, creditOverride: 25),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      await pumpUntilFound(tester, find.text('استرداد نقدي للعميل'));
      await pumpUntilFound(tester, find.byType(CustomerCreditRefundEntry));
      await pumpUntilFound(tester, refundButtonFinder());
      expect(find.textContaining('الرصيد الدائن'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
        isNotNull,
      );
    });

    testWidgets('C) zero credit disables refund action per Step 2.3 semantics',
        (tester) async {
      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(detail: detail, creditOverride: 0),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      await pumpUntilFound(tester, refundButtonFinder());
      expect(find.textContaining('لا يوجد رصيد دائن'), findsWidgets);
      expect(
        tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
        isNull,
      );
    });

    testWidgets('D) general/default customer does not show refund entry',
        (tester) async {
      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: 1,
        customerName: 'زبون عام',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(detail: detail, creditOverride: 20),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      await pumpUntilFound(
          tester, find.textContaining('تفاصيل الفاتورة INV-STEP-2-5'));
      expect(find.text('استرداد نقدي للعميل'), findsNothing);
      expect(find.byType(CustomerCreditRefundEntry), findsNothing);
    });

    testWidgets('E) opening invoice details performs zero REFUND writes',
        (tester) async {
      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Customer',
      );
      var beforeRefunds = 0;

      await tester.runAsync(() async {
        beforeRefunds = (await (db.select(db.customerTransactions)
                  ..where((t) => t.type.equals('REFUND')))
                .get())
            .length;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(detail: detail, creditOverride: 15),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );
      await pumpUntilFound(tester, find.byType(CustomerCreditRefundEntry));

      var afterRefunds = 0;
      await tester.runAsync(() async {
        afterRefunds = (await (db.select(db.customerTransactions)
                  ..where((t) => t.type.equals('REFUND')))
                .get())
            .length;
      });
      expect(afterRefunds, beforeRefunds);
    });

    test('F) opening refund dialog state causes zero REFUND writes', () async {
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
      container.read(customerRefundSettlementProvider.notifier).init(
            customerId: customerId,
            customerName: 'Invoice Customer',
            availableCredit: 20,
          );
      container
          .read(customerRefundSettlementProvider.notifier)
          .setAmountText('5');
      final afterRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds);
    });

    test('G) invalid refund amount performs zero service calls', () async {
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
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider.overrideWithValue(service),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('abc');
      expect(await notifier.submit(), isFalse);
      expect(callCount, 0);
    });

    test('H) valid refund routes through CustomerRefundSettlementService',
        () async {
      await seedCredit(credit: 20);
      var serviceCalls = 0;
      int? capturedReturnId;
      final service = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          serviceCalls++;
          capturedReturnId = returnId;
          await db.customerAccountsDao.recordRefundInTransaction(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
        },
      );
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider.overrideWithValue(service),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('10');
      expect(await notifier.submit(), isTrue);
      expect(serviceCalls, 1);
      expect(capturedReturnId, isNull);
    });

    test('I) refund amount cannot exceed authoritative customer credit',
        () async {
      await seedCredit(credit: 10);
      final service = CustomerRefundSettlementService(db);
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider.overrideWithValue(service),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: 10,
      );
      notifier.setAmountText('15');
      expect(await notifier.submit(), isFalse);
      expect(
        container.read(customerRefundSettlementProvider)!.errorMessage,
        'مبلغ الاسترداد يتجاوز الرصيد الدائن المتاح',
      );
    });

    test('J) successful refund creates exactly one REFUND transaction',
        () async {
      await seedCredit(credit: 20);
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider
              .overrideWithValue(CustomerRefundSettlementService(db)),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final before = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('7');
      expect(await notifier.submit(), isTrue);
      final after = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(after, before + 1);
    });

    test('K) refund remains aggregate-credit based when returnId is null',
        () async {
      await seedCredit(credit: 20);
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider
              .overrideWithValue(CustomerRefundSettlementService(db)),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('6');
      expect(await notifier.submit(), isTrue);
      final refunds = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('REFUND')))
          .get();
      expect(refunds.last.referenceId, isNull);
    });

    testWidgets('L) invoice ID is not passed as returnId', (tester) async {
      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(detail: detail, creditOverride: 12),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      await pumpUntilFound(tester, find.byType(CustomerCreditRefundEntry));
      final entry = tester.widget<CustomerCreditRefundEntry>(
          find.byType(CustomerCreditRefundEntry));
      expect(entry.returnId, isNull);
      expect(entry.returnLabel, isNull);
      expect(entry.returnId, isNot(invoiceId));
    });

    testWidgets('M) sale_item_returns ID is not passed as returnId',
        (tester) async {
      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(detail: detail, creditOverride: 12),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      await pumpUntilFound(tester, find.byType(CustomerCreditRefundEntry));
      final entry = tester.widget<CustomerCreditRefundEntry>(
          find.byType(CustomerCreditRefundEntry));
      expect(entry.returnId, isNull);
      expect(entry.returnId, isNot(detail.lines.first.id));
    });

    test('N) cash ledger derives exactly one CUSTOMER_REFUND from REFUND',
        () async {
      await seedCredit(credit: 20);
      const ledgerFilter = CashLedgerFilter(
        page: 0,
        pageSize: 1000,
        dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
      final ledger = FinancialLedgerRepository(db);
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider
              .overrideWithValue(CustomerRefundSettlementService(db)),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final before = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .length;
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('8');
      expect(await notifier.submit(), isTrue);
      final after = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .length;
      expect(after, before + 1);
    });

    test('O) invoice UI path does not write cash ledger directly', () async {
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
      final container = ProviderContainer(
        overrides: [
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      await container.read(customerAvailableCreditProvider(customerId).future);
      final after = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .length;
      expect(after, before);
    });

    test('P) failure preserves draft and shows mapped Arabic error', () async {
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
            CustomerRefundSettlementFailure.noCustomerCredit,
            'forced',
          );
        },
      );
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider.overrideWithValue(service),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: 20,
      );
      notifier.setAmountText('10');
      notifier.setNote('invoice note');
      expect(await notifier.submit(), isFalse);
      final state = container.read(customerRefundSettlementProvider)!;
      expect(state.amountText, '10');
      expect(state.note, 'invoice note');
      expect(
        state.errorMessage,
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.noCustomerCredit,
        ),
      );
    });

    test('Q) successful settlement refreshes credit provider state', () async {
      await seedCredit(credit: 20);
      final container = ProviderContainer(
        overrides: [
          customerRefundSettlementServiceProvider
              .overrideWithValue(CustomerRefundSettlementService(db)),
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      );
      addTearDown(container.dispose);
      final before = await container
          .read(customerAvailableCreditProvider(customerId).future);
      expect(before, closeTo(20, 0.001));
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Invoice Customer',
        availableCredit: before,
      );
      notifier.setAmountText('20');
      expect(await notifier.submit(), isTrue);
      final after = await container
          .read(customerAvailableCreditProvider(customerId).future);
      expect(after, closeTo(0, 0.001));
    });

    testWidgets('R) existing partial return section remains intact',
        (tester) async {
      final detail = buildDetail(
        id: invoiceId,
        detailCustomerId: customerId,
        customerName: 'Invoice Customer',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(detail: detail, creditOverride: 10),
          child: MaterialApp(
            home: InvoiceDetailsDialog(invoiceId: invoiceId),
          ),
        ),
      );

      await pumpUntilFound(tester, find.text('الإرجاع الجزئي'));
      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('إعادة طباعة الفاتورة'), findsOneWidget);
    });
  });
}
