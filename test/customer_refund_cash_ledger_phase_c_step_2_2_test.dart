import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_account_service.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';

void main() {
  late AppDatabase db;
  late CustomerRefundSettlementService settlementService;
  late PartialReturnService partialService;
  late FinancialLedgerRepository ledger;

  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );
  late int customerId;
  late int productId;
  late int invoiceId;
  const returnedByUserId = 1;

  setUp(() async {
    db = AppDatabase.test();
    settlementService = CustomerRefundSettlementService(db);
    partialService = PartialReturnService(db);
    ledger = FinancialLedgerRepository(db);

    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('Refund Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Refund Product'),
            barcode: Value('CRF-1'),
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

  Future<int> returnTxnCount([int? cid]) async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) =>
              t.customerId.equals(cid ?? customerId) & t.type.equals('RETURN')))
        .get();
    return rows.length;
  }

  Future<int> createCreditInvoice({
    required int customer,
    double debtAmount = 100,
  }) async {
    final id = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('CRF-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(debtAmount),
        total: Value(debtAmount),
        debtAmount: Value(debtAmount),
        customerId: Value(customer),
        paymentMethod: const Value('DEBT'),
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

  Future<void> seedCredit100() async {
    invoiceId =
        await createCreditInvoice(customer: customerId, debtAmount: 100);
    await db.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: 200,
      note: 'overpayment',
    );
    expect(await balance(), -100);
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

  Future<List<CashLedgerEvent>> customerRefundLedgerEvents() async {
    final page = await ledger.getEntries(ledgerFilter);
    return page.entries
        .where((e) => e.eventType == CashLedgerEventType.customerRefund)
        .toList();
  }

  group('Phase C Step 2.2 customer refund cash ledger', () {
    test('A) customer REFUND produces exactly one CUSTOMER_REFUND event',
        () async {
      await seedCredit100();
      await settlementService.settleCredit(customerId: customerId, amount: 100);
      expect(await refundTxnCount(), 1);
      final events = await customerRefundLedgerEvents();
      expect(events.length, 1);
      expect(events.single.eventType, CashLedgerEventType.customerRefund);
    });

    test('B) amount is positive magnitude', () async {
      await seedCredit100();
      await settlementService.settleCredit(customerId: customerId, amount: 40);
      final event = (await customerRefundLedgerEvents()).single;
      expect(event.amount, 40);
      expect(event.amount, greaterThan(0));
    });

    test('C) direction is outflow and summary totalOutflow increases',
        () async {
      await seedCredit100();
      final summaryBefore = await ledger.getSummary(ledgerFilter);
      await settlementService.settleCredit(customerId: customerId, amount: 40);
      final event = (await customerRefundLedgerEvents()).single;
      expect(event.isInflow, isFalse);
      expect(event.direction.code, 'outflow');
      final summaryAfter = await ledger.getSummary(ledgerFilter);
      expect(summaryAfter.totalOutflow, summaryBefore.totalOutflow + 40);
    });

    test('D) customer RETURN produces zero CUSTOMER_REFUND events', () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      final items = await db.salesDao.getItemsForInvoice(invoiceId);
      final saleItemId = items.single.id;
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          PartialReturnLine(
              saleItemId: saleItemId,
              productId: productId,
              quantity: 4,
              unitPrice: 10,
              unitCost: 5)
        ],
      );
      expect(await customerRefundLedgerEvents(), isEmpty);
    });

    test('E) PAYMENT produces zero CUSTOMER_REFUND events', () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      await CustomerAccountService(db)
          .processPayment(customerId: customerId, amount: 40);
      expect(await customerRefundLedgerEvents(), isEmpty);
    });

    test('F) SALE produces zero CUSTOMER_REFUND events', () async {
      await createCreditInvoice(customer: customerId, debtAmount: 100);
      expect(await customerRefundLedgerEvents(), isEmpty);
    });

    test('G) multiple REFUND rows produce one CUSTOMER_REFUND per REFUND',
        () async {
      await seedCredit100();
      await settlementService.settleCredit(customerId: customerId, amount: 40);
      await settlementService.settleCredit(customerId: customerId, amount: 60);
      expect(await refundTxnCount(), 2);
      expect((await customerRefundLedgerEvents()).length, 2);
    });

    test('H) ledger_id is deterministic CUSTOMER_REFUND:<transaction-id>',
        () async {
      await seedCredit100();
      await settlementService.settleCredit(customerId: customerId, amount: 25);
      final txn = (await db.customerAccountsDao.getHistory(customerId))
          .firstWhere((t) => t.type == 'REFUND');
      expect((await customerRefundLedgerEvents()).single.id,
          'CUSTOMER_REFUND:${txn.id}');
    });

    test('I) reference_type is customer_transaction', () async {
      await seedCredit100();
      await settlementService.settleCredit(customerId: customerId, amount: 25);
      expect((await customerRefundLedgerEvents()).single.referenceType,
          'customer_transaction');
    });

    test('J) reference_id is customer_transactions.id', () async {
      await seedCredit100();
      await settlementService.settleCredit(customerId: customerId, amount: 25);
      final txn = (await db.customerAccountsDao.getHistory(customerId))
          .firstWhere((t) => t.type == 'REFUND');
      expect((await customerRefundLedgerEvents()).single.referenceId, txn.id);
    });

    test('K) customer_id is correct', () async {
      await seedCredit100();
      await settlementService.settleCredit(customerId: customerId, amount: 25);
      expect(
          (await customerRefundLedgerEvents()).single.customerId, customerId);
    });

    test('L) return-linked REFUND resolves invoice_id to original_invoice_id',
        () async {
      final returnId = await postReturnCredit100();
      await settlementService.settleCredit(
          customerId: customerId, amount: 10, returnId: returnId);
      expect((await customerRefundLedgerEvents()).single.invoiceId, invoiceId);
    });

    test('M) rollback produces zero REFUND and zero CUSTOMER_REFUND events',
        () async {
      await seedCredit100();
      final failingService =
          CustomerRefundSettlementService(db, postRefundHook: () async {
        throw Exception('forced');
      });
      await expectLater(
          failingService.settleCredit(customerId: customerId, amount: 40),
          throwsA(isA<CustomerRefundSettlementException>()));
      expect(await refundTxnCount(), 0);
      expect(await customerRefundLedgerEvents(), isEmpty);
    });

    test('N) accounting failure produces zero REFUND and zero CUSTOMER_REFUND',
        () async {
      await seedCredit100();
      final failingService = CustomerRefundSettlementService(db,
          refundInTransactionOverride: (
              {required int customerId,
              required double amount,
              int? returnId,
              String? note}) async {
        throw Exception('forced');
      });
      await expectLater(
          failingService.settleCredit(customerId: customerId, amount: 40),
          throwsA(isA<CustomerRefundSettlementException>()));
      expect(await refundTxnCount(), 0);
      expect(await customerRefundLedgerEvents(), isEmpty);
    });

    test('O) supplier SUPPLIER_REFUND remains unchanged', () async {
      final supplierSettlement = SupplierRefundSettlementService(db);
      final supplierReturnService = SupplierReturnService(db);
      final supplierId = await db
          .into(db.suppliers)
          .insert(const SuppliersCompanion(name: Value('Spot Supplier')));
      final supplierProductId = await db
          .into(db.products)
          .insert(const ProductsCompanion(name: Value('Spot Part')));
      final purchaseInvoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
            supplierId: Value(supplierId),
            purchaseDate: Value(DateTime(2026, 3, 1)),
            total: const Value(50),
            paidAmount: const Value(0),
            debtAmount: const Value(50)),
        items: [
          {'productId': supplierProductId, 'qty': 10.0, 'cost': 5.0}
        ],
      );
      final purchaseItems =
          await db.purchasesDao.getItemsForInvoice(purchaseInvoiceId);
      await SupplierAccountService(db)
          .processPayment(supplierId: supplierId, amount: 50);
      await supplierReturnService
          .postPurchaseLinkedReturn(SupplierReturnPostingInput(
        supplierId: supplierId,
        purchaseInvoiceId: purchaseInvoiceId,
        lines: [
          SupplierReturnPostingLine(
              purchaseItemId: purchaseItems.single.id, quantity: 4)
        ],
      ));
      await supplierSettlement.settleCredit(supplierId: supplierId, amount: 20);
      final supplierEvents = (await ledger.getEntries(ledgerFilter))
          .entries
          .where((e) => e.eventType == CashLedgerEventType.supplierRefund)
          .toList();
      expect(supplierEvents.length, 1);
      expect(supplierEvents.single.isInflow, isTrue);
    });

    test('P) partial goods return path does not produce CUSTOMER_REFUND',
        () async {
      invoiceId =
          await createCreditInvoice(customer: customerId, debtAmount: 100);
      final items = await db.salesDao.getItemsForInvoice(invoiceId);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          PartialReturnLine(
              saleItemId: items.single.id,
              productId: productId,
              quantity: 4,
              unitPrice: 10,
              unitCost: 5)
        ],
      );
      expect(await returnTxnCount(), 1);
      expect(await refundTxnCount(), 0);
      expect(await customerRefundLedgerEvents(), isEmpty);
    });
  });
}
