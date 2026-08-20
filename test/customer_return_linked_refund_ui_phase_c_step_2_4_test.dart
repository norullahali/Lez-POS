import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/features/customers/providers/customer_accounts_provider.dart';
import 'package:lez_pos/features/customers/providers/customer_refund_settlement_provider.dart';
import 'package:lez_pos/features/customers/screens/widgets/customer_credit_refund_entry.dart';
import 'package:lez_pos/features/customers/utils/customer_refund_settlement_messages.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/returns/models/customer_return_history_models.dart';
import 'package:lez_pos/features/returns/providers/customer_return_detail_provider.dart';
import 'package:lez_pos/features/returns/repositories/customer_return_read_repository.dart';
import 'package:lez_pos/features/returns/screens/widgets/customer_return_detail_dialog.dart';

void main() {
  group('Phase C Step 2.4 return-linked customer refund entry', () {
    late AppDatabase db;
    late int customerId;
    late int productId;
    late int invoiceId;
    late CustomerReturnReadRepository readRepo;

    Future<void> seedCredit({double credit = 20}) async {
      invoiceId = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value('RL-${DateTime.now().microsecondsSinceEpoch}'),
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

    Future<int> seedLinkedReturn({double returnTotal = 50}) async {
      await seedCredit();
      final returnId = await db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              originalInvoiceId: Value(invoiceId),
              returnNumber:
                  Value('RET-LINK-${DateTime.now().microsecondsSinceEpoch}'),
              total: Value(returnTotal),
              reason: const Value('test linked return'),
            ),
          );
      await db.into(db.customerReturnItems).insert(
            CustomerReturnItemsCompanion.insert(
              returnId: returnId,
              productId: productId,
              productName: 'UI Product',
              quantity: 10,
              unitPrice: 5,
              total: returnTotal,
            ),
          );
      return returnId;
    }

    Future<int> seedUnlinkedReturn() async {
      return db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              returnNumber:
                  Value('RET-UNLINK-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(10),
              reason: const Value('manual return'),
            ),
          );
    }

    setUp(() async {
      db = AppDatabase.test();
      readRepo = CustomerReturnReadRepository(db);
      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Return Customer')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('UI Product'),
              currentStock: Value(100),
              costPrice: Value(5),
            ),
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
          customerReturnReadRepositoryProvider.overrideWithValue(readRepo),
        ],
      );
    }

    Finder refundButtonFinder() =>
        find.widgetWithText(ElevatedButton, 'استرداد من العميل');

    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      int maxAttempts = 30,
    }) async {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester.any(finder)) {
          return;
        }
      }
      fail('Timed out waiting for $finder');
    }

    testWidgets('A) eligible customer return opens refund-capable detail UI',
        (tester) async {
      late int returnId;
      late CustomerReturnDetail detail;
      late double availableCredit;
      var beforeRefunds = 0;

      await tester.runAsync(() async {
        returnId = await seedLinkedReturn();
        final loaded = await readRepo.getCustomerReturnDetail(returnId);
        expect(loaded, isNotNull);
        expect(loaded!.isRefundLinkEligible, isTrue);
        detail = loaded;
        final balance = await db.customerAccountsDao
            .calculateBalanceFromTransactions(customerId);
        availableCredit = balance < 0 ? -balance : 0.0;
        expect(availableCredit, greaterThan(0));
        beforeRefunds = (await (db.select(db.customerTransactions)
                  ..where((t) => t.type.equals('REFUND')))
                .get())
            .length;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            customerReturnReadRepositoryProvider.overrideWithValue(readRepo),
            customerAccountsDaoProvider
                .overrideWithValue(db.customerAccountsDao),
            customerReturnDetailProvider(returnId)
                .overrideWith((ref) async => detail),
            customerAvailableCreditProvider(customerId)
                .overrideWith((ref) async => availableCredit),
          ],
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: 900,
                height: 700,
                child: CustomerReturnDetailDialog(returnId: returnId),
              ),
            ),
          ),
        ),
      );

      await pumpUntilFound(tester, find.textContaining('تفاصيل مرتجع'));
      expect(find.textContaining('قيمة المرتجع'), findsOneWidget);
      expect(find.textContaining(detail.displayReturnNumber), findsOneWidget);
      await pumpUntilFound(tester, find.byType(CustomerCreditRefundEntry));

      final entryFinder = find.byType(CustomerCreditRefundEntry);
      final entry = tester.widget<CustomerCreditRefundEntry>(entryFinder.first);
      expect(entry.customerId, customerId);
      expect(entry.returnId, returnId);
      expect(entry.returnLabel, detail.displayReturnNumber);

      await pumpUntilFound(tester, refundButtonFinder());
      expect(find.textContaining('الرصيد الدائن'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
        isNotNull,
      );

      var afterRefunds = 0;
      await tester.runAsync(() async {
        afterRefunds = (await (db.select(db.customerTransactions)
                  ..where((t) => t.type.equals('REFUND')))
                .get())
            .length;
      });
      expect(afterRefunds, beforeRefunds);
    });

    test('B) customer is correctly resolved from original invoice', () async {
      final returnId = await seedLinkedReturn();
      final detail = await readRepo.getCustomerReturnDetail(returnId);
      expect(detail, isNotNull);
      expect(detail!.customerId, customerId);
      expect(detail.customerName, 'Return Customer');
      expect(detail.originalInvoiceId, invoiceId);
      expect(detail.isRefundLinkEligible, isTrue);
    });

    test('C) correct returnId reaches the existing refund flow', () async {
      final returnId = await seedLinkedReturn();
      int? capturedReturnId;
      final service = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          capturedReturnId = returnId;
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
        customerName: 'Return Customer',
        availableCredit: 20,
        returnId: returnId,
        returnLabel: 'RET-LINK-TEST',
      );
      notifier.setAmountText('10');
      expect(await notifier.submit(), isTrue);
      expect(capturedReturnId, returnId);
    });

    test('D) correct returnLabel is displayed in dialog state', () async {
      final returnId = await seedLinkedReturn();
      final detail = await readRepo.getCustomerReturnDetail(returnId);
      final container = ProviderContainer(
        overrides: [
          customerReturnReadRepositoryProvider.overrideWithValue(readRepo),
        ],
      );
      addTearDown(container.dispose);
      container.read(customerRefundSettlementProvider.notifier).init(
            customerId: customerId,
            customerName: detail!.displayCustomerName,
            availableCredit: 20,
            returnId: returnId,
            returnLabel: detail.displayReturnNumber,
          );
      final state = container.read(customerRefundSettlementProvider);
      expect(state!.returnId, returnId);
      expect(state.returnLabel, detail.displayReturnNumber);
    });

    test('E) return/customer mismatch is rejected by canonical service',
        () async {
      final returnId = await seedLinkedReturn();
      final otherCustomerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('Other Customer')),
          );
      await db.customerAccountsDao.recordPayment(
        customerId: otherCustomerId,
        amount: 100,
        note: 'credit for mismatch test',
      );
      final service = CustomerRefundSettlementService(db);
      expect(
        () => service.settleCredit(
          customerId: otherCustomerId,
          amount: 5,
          returnId: returnId,
        ),
        throwsA(
          predicate<CustomerRefundSettlementException>(
            (e) =>
                e.code ==
                CustomerRefundSettlementFailure.returnCustomerMismatch,
          ),
        ),
      );
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.returnCustomerMismatch,
        ),
        'المرتجع لا ينتمي إلى هذا العميل',
      );
    });

    test('F) missing/unlinked return cannot settle with returnId', () async {
      final returnId = await seedUnlinkedReturn();
      final detail = await readRepo.getCustomerReturnDetail(returnId);
      expect(detail!.isRefundLinkEligible, isFalse);
      await seedCredit();
      final service = CustomerRefundSettlementService(db);
      expect(
        () => service.settleCredit(
          customerId: customerId,
          amount: 5,
          returnId: returnId,
        ),
        throwsA(
          predicate<CustomerRefundSettlementException>(
            (e) => e.code == CustomerRefundSettlementFailure.returnNotFound,
          ),
        ),
      );
    });

    testWidgets('G) no customer credit disables refund entry', (tester) async {
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
                  customerName: 'Return Customer',
                  returnId: 1,
                  returnLabel: 'RET-LINK',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(refundButtonFinder()).onPressed,
        isNull,
      );
    });

    test('H) partial available-credit refund works through canonical service',
        () async {
      final returnId = await seedLinkedReturn();
      final container =
          containerWithService(CustomerRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Return Customer',
        availableCredit: 20,
        returnId: returnId,
        returnLabel: 'RET-LINK',
      );
      notifier.setAmountText('12');
      expect(await notifier.submit(), isTrue);
      final refunds = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('REFUND')))
          .get();
      expect(refunds.last.referenceId, returnId);
      expect(refunds.last.amount, closeTo(12, 0.001));
    });

    test('I) full available-credit refund works through canonical service',
        () async {
      final returnId = await seedLinkedReturn();
      final container =
          containerWithService(CustomerRefundSettlementService(db));
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Return Customer',
        availableCredit: 20,
        returnId: returnId,
        returnLabel: 'RET-LINK',
      );
      notifier.setAmountText('20');
      expect(await notifier.submit(), isTrue);
      final credit = await container
          .read(customerAvailableCreditProvider(customerId).future);
      expect(credit, closeTo(0, 0.001));
    });

    test('J) UI does not directly write customer_transactions', () async {
      final returnId = await seedLinkedReturn();
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
      final before = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Return Customer',
        availableCredit: 20,
        returnId: returnId,
        returnLabel: 'RET-LINK',
      );
      notifier.setAmountText('7');
      expect(await notifier.submit(), isTrue);
      expect(serviceCalls, 1);
      final after = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(after, before + 1);
    });

    test('K) UI does not directly write Cash Ledger', () async {
      final returnId = await seedLinkedReturn();
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
        customerName: 'Return Customer',
        availableCredit: 20,
        returnId: returnId,
        returnLabel: 'RET-LINK',
      );
      notifier.setAmountText('6');
      expect(await notifier.submit(), isTrue);
      final after = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .length;
      expect(after, before + 1);
    });

    test('L) existing Step 2.3 profile refund remains unchanged', () async {
      await seedCredit();
      final container = containerWithService(
        CustomerRefundSettlementService(db),
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(customerRefundSettlementProvider.notifier);
      notifier.init(
        customerId: customerId,
        customerName: 'Return Customer',
        availableCredit: 20,
      );
      expect(
          container.read(customerRefundSettlementProvider)!.returnId, isNull);
      notifier.setAmountText('5');
      expect(await notifier.submit(), isTrue);
      final refunds = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('REFUND')))
          .get();
      expect(refunds.last.referenceId, isNull);
    });

    test('M) opening return detail/refund entry causes zero financial writes',
        () async {
      final returnId = await seedLinkedReturn();
      final beforeRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      await readRepo.getCustomerReturnDetail(returnId);
      await ProviderContainer(
        overrides: [
          customerAccountsDaoProvider.overrideWithValue(db.customerAccountsDao),
        ],
      ).read(customerAvailableCreditProvider(customerId).future);
      final afterRefunds = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;
      expect(afterRefunds, beforeRefunds);
    });

    test(
        'N) successful linked refund produces derived CUSTOMER_REFUND with returnId',
        () async {
      final returnId = await seedLinkedReturn();
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
        customerName: 'Return Customer',
        availableCredit: 20,
        returnId: returnId,
        returnLabel: 'RET-LINK',
      );
      notifier.setAmountText('8');
      expect(await notifier.submit(), isTrue);
      final refunds = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('REFUND')))
          .get();
      expect(refunds.last.referenceId, returnId);
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
