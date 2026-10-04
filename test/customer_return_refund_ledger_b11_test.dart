import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_refund_settlement_service.dart';
import 'package:lez_pos/core/services/manual_return_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/core/services/pos_sale_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';

import 'support/customer_manual_return_test_keys.dart';
import 'support/customer_quick_return_test_keys.dart';
import 'support/customer_refund_test_keys.dart';

void main() {
  const returnedByUserId = 1;
  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  group('B11 RETURN_REFUND ledger semantics', () {
    late AppDatabase db;
    late FinancialLedgerRepository ledger;
    late PartialReturnService partialService;
    late CustomerRefundSettlementService settlementService;
    late int customerId;
    late int productId;

    Future<(int count, double total)> returnRefundStats() async {
      final page = await ledger.getEntries(ledgerFilter);
      final events = page.entries
          .where((e) => e.eventType == CashLedgerEventType.returnRefund)
          .toList();
      return (
        events.length,
        events.fold<double>(0, (sum, e) => sum + e.amount),
      );
    }

    Future<(int count, double total)> customerRefundStats() async {
      final page = await ledger.getEntries(ledgerFilter);
      final events = page.entries
          .where((e) => e.eventType == CashLedgerEventType.customerRefund)
          .toList();
      return (
        events.length,
        events.fold<double>(0, (sum, e) => sum + e.amount),
      );
    }

    Future<int> returnTxnCount() async {
      final rows = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('RETURN')))
          .get();
      return rows.length;
    }

    Future<int> createCreditInvoice({
      required double debtAmount,
      String? invoiceNumber,
    }) async {
      final id = await db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber: Value(
            invoiceNumber ?? 'B11-CR-${DateTime.now().microsecondsSinceEpoch}',
          ),
          subtotal: Value(debtAmount),
          total: Value(debtAmount),
          debtAmount: Value(debtAmount),
          customerId: Value(customerId),
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
      await db.customerAccountsDao.recordSale(
        customerId: customerId,
        amount: debtAmount,
        invoiceId: id,
        note: 'B11 credit sale',
      );
      return id;
    }

    Future<int> createCashInvoice({required double total}) async {
      return db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          invoiceNumber:
              Value('B11-CASH-${DateTime.now().microsecondsSinceEpoch}'),
          subtotal: Value(total),
          total: Value(total),
          debtAmount: const Value(0),
          cashPaid: Value(total),
          customerId: Value(customerId),
          paymentMethod: const Value('CASH'),
        ),
        items: [
          {
            'productId': productId,
            'qty': 10.0,
            'price': total / 10,
            'cost': 5.0,
          },
        ],
      );
    }

    Future<void> partialReturn({
      required int invoiceId,
      required double quantity,
      required double unitPrice,
    }) async {
      final saleItemId =
          (await db.salesDao.getItemsForInvoice(invoiceId)).single.id;
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [
          PartialReturnLine(
            saleItemId: saleItemId,
            productId: productId,
            quantity: quantity,
            unitPrice: unitPrice,
            unitCost: 5,
          ),
        ],
      );
    }

    Future<int> linkedCustomerReturnId(int invoiceId) async {
      final row = await db.returnsDao.findCustomerReturnByOriginalInvoiceId(
        invoiceId,
      );
      expect(row, isNotNull);
      return row!.id;
    }

    setUp(() async {
      db = AppDatabase.test();
      ledger = FinancialLedgerRepository(db);
      partialService = PartialReturnService(db);
      settlementService = CustomerRefundSettlementService(db);

      customerId = await db.into(db.customers).insert(
            const CustomersCompanion(name: Value('B11 Ledger Customer')),
          );
      productId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('B11 Ledger Product'),
              barcode: Value('B11-LEDGER'),
              currentStock: Value(100),
              costPrice: Value(5),
              sellPrice: Value(10),
            ),
          );
    });

    tearDown(() async {
      await db.close();
    });

    test('1) full credit return suppresses RETURN_REFUND', () async {
      final invoiceId = await createCreditInvoice(debtAmount: 100);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 100,
        note: 'pay before full return',
      );

      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'full credit return',
        returnedByUserId: returnedByUserId,
      );

      final stats = await returnRefundStats();
      expect(stats.$1, 0);
      expect(stats.$2, 0);
      expect(await returnTxnCount(), 1);
    });

    test('2) full cash return shows RETURN_REFUND', () async {
      final invoiceId = await createCashInvoice(total: 100);
      await db.returnsDao.returnFullSaleInvoice(
        invoiceId,
        note: 'full cash return',
        returnedByUserId: returnedByUserId,
      );

      final stats = await returnRefundStats();
      expect(stats.$1, greaterThan(0));
      expect(stats.$2, closeTo(100, 0.001));
      expect(await returnTxnCount(), 0);
    });

    test('3) partial credit without settlement suppresses RETURN_REFUND',
        () async {
      final invoiceId = await createCreditInvoice(debtAmount: 100);
      await partialReturn(invoiceId: invoiceId, quantity: 4, unitPrice: 10);

      final stats = await returnRefundStats();
      expect(stats.$1, 0);
      expect(stats.$2, 0);
      expect(await returnTxnCount(), 1);

      final returnTxn = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('RETURN')))
          .getSingle();
      final sirId = (await db.select(db.saleItemReturns).get()).single.id;
      expect(returnTxn.referenceId, sirId);
    });

    test('4) partial credit + settlement totals 40 not 80', () async {
      const settlementAmount = 40.0;
      final invoiceId = await createCreditInvoice(debtAmount: 100);
      await db.customerAccountsDao.recordPayment(
        customerId: customerId,
        amount: 100,
        note: 'pay before partial return',
      );
      await partialReturn(invoiceId: invoiceId, quantity: 4, unitPrice: 10);

      final returnId = await linkedCustomerReturnId(invoiceId);
      await settlementService.settleCredit(
        idempotencyKey: refundTestIdempotencyKey(),
        customerId: customerId,
        amount: settlementAmount,
        returnId: returnId,
      );

      final returnRefund = await returnRefundStats();
      final customerRefund = await customerRefundStats();
      final summary = await ledger.getSummary(ledgerFilter);

      expect(returnRefund.$1, 0);
      expect(returnRefund.$2, 0);
      expect(customerRefund.$1, 1);
      expect(customerRefund.$2, closeTo(settlementAmount, 0.001));
      expect(summary.totalOutflow, closeTo(settlementAmount, 0.001));
      expect(summary.totalOutflow, isNot(closeTo(80, 0.001)));
    });

    test('5) partial cash return shows RETURN_REFUND and no RETURN txn',
        () async {
      const refundAmount = 40.0;
      final invoiceId = await createCashInvoice(total: 100);
      await partialReturn(invoiceId: invoiceId, quantity: 4, unitPrice: 10);

      final stats = await returnRefundStats();
      expect(stats.$1, greaterThan(0));
      expect(stats.$2, closeTo(refundAmount, 0.001));
      expect(await returnTxnCount(), 0);
    });

    test('6) Quick Return shows RETURN_REFUND only', () async {
      const refundAmount = 20.0;
      await PosSaleService(db).processQuickReturn(
        idempotencyKey: b9QuickReturnIdempotencyKey(),
        productId: productId,
        quantity: 2,
        refundAmount: refundAmount,
        userId: returnedByUserId,
        reason: 'B11 quick return',
      );

      final returnRefund = await returnRefundStats();
      final customerRefund = await customerRefundStats();
      expect(returnRefund.$1, 1);
      expect(returnRefund.$2, closeTo(refundAmount, 0.001));
      expect(customerRefund.$1, 0);
      expect(customerRefund.$2, 0);
    });

    test('7) manual return production semantics suppress RETURN_REFUND',
        () async {
      await ManualReturnService(db).processManualReturn(
        idempotencyKey: b10ManualReturnIdempotencyKey(),
        productId: productId,
        quantity: 1,
        unitPrice: 0,
        reason: 'manual zero price',
        userId: returnedByUserId,
      );

      final stats = await returnRefundStats();
      expect(stats.$1, 0);
      expect(stats.$2, 0);
    });

    test('8) multiple partial credit batches suppress RETURN_REFUND', () async {
      final invoiceId = await createCreditInvoice(debtAmount: 100);
      await partialReturn(invoiceId: invoiceId, quantity: 2, unitPrice: 10);
      await partialReturn(invoiceId: invoiceId, quantity: 2, unitPrice: 10);

      final stats = await returnRefundStats();
      expect(stats.$1, 0);
      expect(stats.$2, 0);
      expect(await returnTxnCount(), 2);
    });

    test('9) cross-invoice RETURN does not suppress other invoice audit',
        () async {
      final creditInvoiceId = await createCreditInvoice(debtAmount: 100);
      await partialReturn(
        invoiceId: creditInvoiceId,
        quantity: 4,
        unitPrice: 10,
      );

      final cashInvoiceId = await createCashInvoice(total: 100);
      await partialReturn(
        invoiceId: cashInvoiceId,
        quantity: 3,
        unitPrice: 10,
      );

      final stats = await returnRefundStats();
      expect(stats.$1, 1);
      expect(stats.$2, closeTo(30, 0.001));
    });

    test('10) historical source rows unchanged after derived ledger read',
        () async {
      final invoiceId = await createCreditInvoice(debtAmount: 100);
      await partialReturn(invoiceId: invoiceId, quantity: 4, unitPrice: 10);

      final auditBefore = (await db.select(db.returnAuditLogs).get()).length;
      final returnTxnBefore = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('RETURN')))
              .get())
          .length;
      final sirBefore = (await db.select(db.saleItemReturns).get()).length;
      final returnTxnRef = (await (db.select(db.customerTransactions)
                ..where((t) => t.type.equals('RETURN')))
              .getSingle())
          .referenceId;
      final sirId = (await db.select(db.saleItemReturns).get()).single.id;
      expect(returnTxnRef, sirId);

      final stats = await returnRefundStats();
      expect(stats.$1, 0);
      expect(stats.$2, 0);

      expect((await db.select(db.returnAuditLogs).get()).length, auditBefore);
      expect(
        (await (db.select(db.customerTransactions)
                  ..where((t) => t.type.equals('RETURN')))
                .get())
            .length,
        returnTxnBefore,
      );
      expect((await db.select(db.saleItemReturns).get()).length, sirBefore);
    });
  });
}
