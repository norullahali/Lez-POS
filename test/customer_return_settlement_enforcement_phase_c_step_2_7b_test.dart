import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/customers/utils/customer_refund_settlement_messages.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';
import 'package:lez_pos/features/returns/models/customer_return_history_models.dart';

void main() {
  late AppDatabase db;
  late CustomerRefundSettlementService settlementService;
  late PartialReturnService partialService;
  late int customerId;
  late int otherCustomerId;
  late int productId;
  late int invoiceId;
  const returnedByUserId = 1;
  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  setUp(() async {
    db = AppDatabase.test();
    settlementService = CustomerRefundSettlementService(db);
    partialService = PartialReturnService(db);

    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Cap Customer')),
        );
    otherCustomerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Other Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Cap Product'),
            barcode: Value('CAP-1'),
            currentStock: Value(100),
            costPrice: Value(5),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance([int? cid]) =>
      db.customerAccountsDao.getBalance(cid ?? customerId);

  Future<int> refundTxnCount([int? cid]) async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('REFUND')))
        .get();
    return rows.length;
  }

  Future<int> logCount() async {
    final rows = await db.select(db.logsTable).get();
    return rows.where((l) => l.actionType == 'CUSTOMER_REFUND').length;
  }

  Future<double> settledAmount(int returnId) async {
    final header = await db.returnsDao.getCustomerReturnById(returnId);
    return header!.settledAmount;
  }

  Future<int> createCreditInvoice({
    required int customer,
    double debtAmount = 100,
    String paymentMethod = 'DEBT',
  }) async {
    final id = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('CAP-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(debtAmount),
        total: Value(debtAmount),
        debtAmount: Value(debtAmount),
        customerId: Value(customer),
        paymentMethod: Value(paymentMethod),
      ),
      items: [
        {
          'productId': productId,
          'qty': 10.0,
          'price': debtAmount / 10,
          'cost': 5.0,
        },
      ],
    );

    if (debtAmount > 0) {
      await db.customerAccountsDao.recordSale(
        customerId: customer,
        amount: debtAmount,
        invoiceId: id,
        note: 'test credit sale',
      );
    }

    return id;
  }

  Future<int> postReturnCredit100() async {
    invoiceId =
        await createCreditInvoice(customer: customerId, debtAmount: 100);
    await db.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: 100,
      note: 'pay before return',
    );
    expect(await balance(), 0);

    await db.returnsDao.returnFullSaleInvoice(
      invoiceId,
      note: 'full return',
      returnedByUserId: returnedByUserId,
    );
    expect(await balance(), -100);

    final returns = await db.select(db.customerReturns).get();
    return returns.single.id;
  }

  Future<List<dynamic>> customerRefundLedgerEvents() async {
    final ledger = FinancialLedgerRepository(db);
    final page = await ledger.getEntries(ledgerFilter);
    return page.entries
        .where((e) => e.eventType == CashLedgerEventType.customerRefund)
        .toList();
  }

  group('Phase C Step 2.7B return cap enforcement', () {
    test('A) return-linked refund within cap succeeds', () async {
      final returnId = await postReturnCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
        returnId: returnId,
      );

      expect(await settledAmount(returnId), 40);
      expect(await refundTxnCount(), 1);
      expect(await balance(), -60);
    });

    test('B) exact return remaining succeeds', () async {
      final returnId = await postReturnCredit100();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 70 WHERE id = ?',
        [returnId],
      );

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 30,
        returnId: returnId,
      );

      expect(await settledAmount(returnId), 100);
    });

    test('C) above remaining return amount fails', () async {
      final returnId = await postReturnCredit100();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 70 WHERE id = ?',
        [returnId],
      );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 31,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsReturnRefundableAmount,
          ),
        ),
      );

      expect(await settledAmount(returnId), 70);
      expect(await refundTxnCount(), 0);
    });

    test('D) multiple partial refunds accumulate settled_amount', () async {
      final returnId = await postReturnCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 20,
        returnId: returnId,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 30,
        returnId: returnId,
      );

      expect(await settledAmount(returnId), 50);
      expect(await refundTxnCount(), 2);
    });

    test('E) fully settled return rejects further refund', () async {
      final returnId = await postReturnCredit100();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 100 WHERE id = ?',
        [returnId],
      );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 1,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.noReturnRefundableAmount,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
    });

    test('F) existing customer credit cap remains enforced', () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 170,
        note: 'partial overpay',
      );
      expect(await balance(), -70);

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 80,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );
    });

    test('G) both customer credit and return cap enforced', () async {
      final returnId = await postReturnCredit100();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 60 WHERE id = ?',
        [returnId],
      );
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 20,
        note: 'extra credit',
      );
      expect(await balance(), closeTo(-120, 0.001));

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 50,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsReturnRefundableAmount,
          ),
        ),
      );
    });

    test('H) successful refund increments settled_amount', () async {
      final returnId = await postReturnCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 25,
        returnId: returnId,
      );

      expect(await settledAmount(returnId), 25);
    });

    test('I) failed pre-check does not increment settled_amount', () async {
      final returnId = await postReturnCredit100();
      await db.customStatement(
        'UPDATE customer_returns SET settled_amount = 90 WHERE id = ?',
        [returnId],
      );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 20,
          returnId: returnId,
        ),
        throwsA(isA<CustomerRefundSettlementException>()),
      );

      expect(await settledAmount(returnId), 90);
      expect(await refundTxnCount(), 0);
    });

    test('J) conditional increment failure rolls back REFUND', () async {
      final returnId = await postReturnCredit100();
      final beforeBalance = await balance();
      final beforeRefunds = await refundTxnCount();
      final beforeSettled = await settledAmount(returnId);
      final beforeLogs = await logCount();
      final beforeLedger = (await customerRefundLedgerEvents()).length;

      final racingService = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          await db.customerAccountsDao.recordRefundInTransaction(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
          );
          await db.customStatement(
            'UPDATE customer_returns SET settled_amount = 100 WHERE id = ?',
            [returnId],
          );
        },
      );

      await expectLater(
        racingService.settleCredit(
          customerId: customerId,
          amount: 50,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.amountExceedsReturnRefundableAmount,
          ),
        ),
      );

      expect(await balance(), beforeBalance);
      expect(await refundTxnCount(), beforeRefunds);
      expect(await settledAmount(returnId), beforeSettled);
      expect(await logCount(), beforeLogs);
      expect((await customerRefundLedgerEvents()).length, beforeLedger);
    });

    test('K) REFUND failure rolls back entire transaction', () async {
      final returnId = await postReturnCredit100();
      final failingService = CustomerRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int customerId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          throw Exception('forced refund failure');
        },
      );

      await expectLater(
        failingService.settleCredit(
          customerId: customerId,
          amount: 10,
          returnId: returnId,
        ),
        throwsA(isA<CustomerRefundSettlementException>()),
      );

      expect(await settledAmount(returnId), 0);
      expect(await refundTxnCount(), 0);
    });

    test('L) customer mismatch remains rejected', () async {
      final returnId = await postReturnCredit100();

      await expectLater(
        settlementService.settleCredit(
          customerId: otherCustomerId,
          amount: 10,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.returnCustomerMismatch,
          ),
        ),
      );
    });

    test('M) missing return remains rejected', () async {
      await postReturnCredit100();

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 10,
          returnId: 999999,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.returnNotFound,
          ),
        ),
      );
    });

    test('N) zero return cap rejects', () async {
      invoiceId = await createCreditInvoice(
        customer: customerId,
        debtAmount: 100,
      );
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 200,
        note: 'credit without return',
      );
      final returnId = await db.into(db.customerReturns).insert(
            CustomerReturnsCompanion(
              originalInvoiceId: Value(invoiceId),
              returnNumber:
                  Value('RET-ZERO-${DateTime.now().microsecondsSinceEpoch}'),
              total: const Value(100),
            ),
          );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 10,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.noReturnRefundableAmount,
          ),
        ),
      );
    });

    test('O) return-linked General Customer remains UI-ineligible', () {
      final detail = CustomerReturnDetail(
        id: 1,
        returnNumber: 'RET-G',
        returnDate: DateTime(2026, 1, 1),
        total: 10,
        reason: '',
        notes: '',
        originalInvoiceId: 5,
        saleInvoiceNumber: 'INV',
        customerId: 1,
        customerName: 'General',
        lines: const [],
      );
      expect(detail.isRefundLinkEligible, isFalse);
    });

    test('P) cash invoice linked return rejects despite unrelated credit',
        () async {
      invoiceId = await createCreditInvoice(
        customer: customerId,
        debtAmount: 0,
        paymentMethod: 'CASH',
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          PartialReturnLine(
            saleItemId:
                (await db.salesDao.getItemsForInvoice(invoiceId)).single.id,
            productId: productId,
            quantity: 2,
            unitPrice: 10,
            unitCost: 5,
          ),
        ],
      );
      final returnId = (await db.select(db.customerReturns).get()).single.id;

      final otherInvoice =
          await createCreditInvoice(customer: customerId, debtAmount: 50);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 100,
        note: 'unrelated credit',
      );
      expect(await balance(), lessThan(0));

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 10,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.noReturnRefundableAmount,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
      expect(otherInvoice, greaterThan(0));
    });

    test('Q) returnId null preserves aggregate-only refund behavior', () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 200,
        note: 'credit only',
      );

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 40,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 60,
      );

      expect(await refundTxnCount(), 2);
      expect(await balance(), 0);
    });

    test('R) historical settled_amount is respected', () async {
      final returnId = await postReturnCredit100();
      await db.customerAccountsDao.recordRefundInTransaction(
        customerId: customerId,
        amount: 35,
        returnId: returnId,
        note: 'historical',
      );
      await db.customStatement(
        '''
        UPDATE customer_returns
        SET settled_amount = COALESCE((
          SELECT SUM(ct.amount)
          FROM customer_transactions ct
          WHERE ct.type = 'REFUND'
            AND ct.reference_id = customer_returns.id
            AND ct.amount > 0
        ), 0)
        WHERE id = ?
        ''',
        [returnId],
      );
      expect(await settledAmount(returnId), 35);

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 65,
        returnId: returnId,
      );

      expect(await settledAmount(returnId), 100);
    });

    test('S) different return documents have independent caps', () async {
      final returnA = await postReturnCredit100();

      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 50);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 50,
        note: 'pay second',
      );
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'second return',
        returnedByUserId: returnedByUserId,
      );
      final returnB = (await (db.select(db.customerReturns)
                ..where((r) => r.id.isNotValue(returnA)))
              .get())
          .single
          .id;

      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 100,
        note: 'restore aggregate credit for dual refunds',
      );

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 60,
        returnId: returnA,
      );
      await settlementService.settleCredit(
        customerId: customerId,
        amount: 25,
        returnId: returnB,
      );

      expect(await settledAmount(returnA), 60);
      expect(await settledAmount(returnB), 25);
    });

    test('T) same-return over-cap race simulation via DAO guard', () async {
      final returnId = await postReturnCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 100,
        returnId: returnId,
      );

      await expectLater(
        settlementService.settleCredit(
          customerId: customerId,
          amount: 1,
          returnId: returnId,
        ),
        throwsA(
          isA<CustomerRefundSettlementException>().having(
            (e) => e.code,
            'code',
            CustomerRefundSettlementFailure.noReturnRefundableAmount,
          ),
        ),
      );

      expect(await refundTxnCount(), 1);
      expect(await settledAmount(returnId), 100);
    });

    test('U) linked REFUND reference_id == customer_returns.id', () async {
      final returnId = await postReturnCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 15,
        returnId: returnId,
      );

      final txn = (await db.customerAccountsDao.getHistory(customerId))
          .firstWhere((t) => t.type == 'REFUND');
      expect(txn.referenceId, returnId);
      expect(txn.amount, 15);
    });

    test('V) RETURN reference_id remains sale_item_returns.id on partial path',
        () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 100,
        note: 'pay',
      );
      final saleItemId =
          (await db.salesDao.getItemsForInvoice(invoiceId)).single.id;
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          PartialReturnLine(
            saleItemId: saleItemId,
            productId: productId,
            quantity: 4,
            unitPrice: 10,
            unitCost: 5,
          ),
        ],
      );

      final returnTxn = (await db.customerAccountsDao.getHistory(customerId))
          .firstWhere((t) => t.type == 'RETURN');
      final saleItemReturnId =
          (await db.select(db.saleItemReturns).get()).single.id;
      expect(returnTxn.referenceId, saleItemReturnId);
      final linkedSaleItemReturn = await (db.select(db.saleItemReturns)
            ..where((r) => r.id.equals(returnTxn.referenceId!)))
          .getSingleOrNull();
      expect(linkedSaleItemReturn, isNotNull);
    });

    test('W) Financial Ledger still derives CUSTOMER_REFUND from REFUND',
        () async {
      final returnId = await postReturnCredit100();

      await settlementService.settleCredit(
        customerId: customerId,
        amount: 12,
        returnId: returnId,
      );

      final events = await customerRefundLedgerEvents();
      expect(events.length, 1);
      expect(events.single.eventType, CashLedgerEventType.customerRefund);
      expect(events.single.amount, closeTo(12, 0.001));
    });

    test('messages map new failure codes to Arabic text', () {
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.noReturnRefundableAmount,
        ),
        'لا يوجد مبلغ متبقٍ قابل للاسترداد على هذا المرتجع',
      );
      expect(
        customerRefundSettlementFailureMessage(
          CustomerRefundSettlementFailure.amountExceedsReturnRefundableAmount,
        ),
        'مبلغ الاسترداد يتجاوز المبلغ المتبقي القابل للاسترداد على هذا المرتجع',
      );
    });
  });
}
