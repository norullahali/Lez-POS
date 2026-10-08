import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/customer_invoice_return_service.dart';
import 'package:lez_pos/core/services/partial_return_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_event_type.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';
import 'package:lez_pos/features/reports/core/models/report_date_preset.dart';
import 'package:lez_pos/features/reports/core/models/report_filter_model.dart';

import 'support/customer_invoice_return_test_keys.dart';

void main() {
  const returnedByUserId = 1;
  const unitPrice = 10.0;
  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  late AppDatabase db;
  late PartialReturnService partialService;
  late CustomerInvoiceReturnService invoiceReturnService;
  late FinancialLedgerRepository ledger;
  late int customerId;
  late int productId;
  late int saleItemId;
  late int invoiceId;

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

  Future<double> returnCreditTotal() async {
    return db.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
      customerId: customerId,
      invoiceId: invoiceId,
    );
  }

  Future<double> absReturnTxnTotal() async {
    final rows = await (db.select(db.customerTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get();
    return rows.fold<double>(0, (sum, row) => sum + row.amount.abs());
  }

  Future<int> returnTxnCount() async {
    return (await (db.select(db.customerTransactions)
              ..where((t) => t.type.equals('RETURN')))
            .get())
        .length;
  }

  PartialReturnLine returnLine({required double quantity, int? itemId}) =>
      PartialReturnLine(
        saleItemId: itemId ?? saleItemId,
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
        unitCost: 5,
      );

  Future<void> seedInvoice({
    required double total,
    required double cashPaid,
    required double debtAmount,
    double cardPaid = 0,
    int? customerOverride,
    double saleQty = 10,
  }) async {
    final cid = customerOverride ?? customerId;
    invoiceId = await db.salesDao.saveSaleInvoice(
      header: SalesInvoicesCompanion(
        invoiceNumber: Value('B17-${DateTime.now().microsecondsSinceEpoch}'),
        subtotal: Value(total),
        total: Value(total),
        debtAmount: Value(debtAmount),
        cashPaid: Value(cashPaid),
        cardPaid: Value(cardPaid),
        customerId: Value(cid),
        paymentMethod: Value(
          debtAmount > 0
              ? (cashPaid > 0 || cardPaid > 0 ? 'MIXED' : 'DEBT')
              : 'CASH',
        ),
      ),
      items: [
        {
          'productId': productId,
          'qty': saleQty,
          'price': total / saleQty,
          'cost': 5.0,
        },
      ],
    );
    saleItemId = (await db.salesDao.getItemsForInvoice(invoiceId)).single.id;
    if (debtAmount > 0 && cid != 1) {
      await db.customerAccountsDao.recordSale(
        customerId: cid,
        amount: debtAmount,
        invoiceId: invoiceId,
        note: 'B17 credit sale',
      );
    }
  }

  setUp(() async {
    db = AppDatabase.test();
    expect(db.schemaVersion, 48);
    partialService = PartialReturnService(db);
    invoiceReturnService = CustomerInvoiceReturnService(db);
    ledger = FinancialLedgerRepository(db);
    customerId = await db.into(db.customers).insert(
          const CustomersCompanion(name: Value('B17 Ledger Customer')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('B17 Product'),
            barcode: Value('B17-PROD'),
            currentStock: Value(100),
            costPrice: Value(5),
            sellPrice: Value(10),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  group('B17 mixed-payment invoice return cash ledger', () {
    test('A) cash-only invoice return 40 shows RETURN_REFUND 40', () async {
      await seedInvoice(total: 100, cashPaid: 100, debtAmount: 0);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      expect(await returnTxnCount(), 0);
      final stats = await returnRefundStats();
      expect(stats.$1, greaterThan(0));
      expect(stats.$2, closeTo(40, 0.001));
    });

    test('B) credit-only invoice return 40 suppresses RETURN_REFUND', () async {
      await seedInvoice(total: 100, cashPaid: 0, debtAmount: 100);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      expect(await returnTxnCount(), 1);
      expect(await absReturnTxnTotal(), closeTo(40, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$1, 0);
      expect(stats.$2, 0);
    });

    test('C) mixed 50/50 return 50 shows RETURN_REFUND 25', () async {
      await seedInvoice(total: 100, cashPaid: 50, debtAmount: 50);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 5)],
      );

      expect(await absReturnTxnTotal(), closeTo(25, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(25, 0.001));
    });

    test('D) mixed 70/30 return 50 shows RETURN_REFUND 35', () async {
      await seedInvoice(total: 100, cashPaid: 70, debtAmount: 30);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 5)],
      );

      expect(await absReturnTxnTotal(), closeTo(15, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(35, 0.001));
    });

    test('E) multiple partial mixed returns cash 10 + 15 = 25', () async {
      await seedInvoice(total: 100, cashPaid: 50, debtAmount: 50);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 2)],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 3)],
      );

      expect(await absReturnTxnTotal(), closeTo(25, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(25, 0.001));
    });

    test('F) partial 40 then full remaining 60 cumulative cash 50', () async {
      await seedInvoice(total: 100, cashPaid: 50, debtAmount: 50);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );
      await partialService.returnAllRemainingSaleInvoice(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B17 full remaining',
      );

      expect(await returnCreditTotal(), closeTo(50, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(50, 0.001));
    });

    test('G) fresh full return mixed 50/50 cash 50 credit 50', () async {
      await seedInvoice(total: 100, cashPaid: 50, debtAmount: 50);
      await invoiceReturnService.processFullReturn(
        idempotencyKey: b16CustomerInvoiceReturnIdempotencyKey(),
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        note: 'B17 fresh full',
      );

      expect(await returnCreditTotal(), closeTo(50, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(50, 0.001));
    });

    test('H) walk-in cash invoice full RETURN_REFUND no RETURN txn', () async {
      // Default seed creates walk-in customer id=1.
      await seedInvoice(
        total: 100,
        cashPaid: 100,
        debtAmount: 0,
        customerOverride: 1,
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      expect(await returnTxnCount(), 0);
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(40, 0.001));
    });

    test('I) debt-only invoice zero cash ledger', () async {
      await seedInvoice(total: 100, cashPaid: 0, debtAmount: 100);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 5)],
      );

      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(0, 0.001));
      expect(await absReturnTxnTotal(), closeTo(50, 0.001));
    });

    test('J) cash-only invoice full cash ledger', () async {
      await seedInvoice(total: 100, cashPaid: 100, debtAmount: 0);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 5)],
      );

      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(50, 0.001));
      expect(await returnTxnCount(), 0);
    });

    test('K) precision cash 33 debt 67 return 10 goods', () async {
      await seedInvoice(total: 100, cashPaid: 33, debtAmount: 67);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 1)],
      );

      expect(await absReturnTxnTotal(), closeTo(6.7, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(3.3, 0.001));
    });

    test('L) credit-only regression B11/B12 suppression preserved', () async {
      await seedInvoice(total: 100, cashPaid: 0, debtAmount: 100);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 4)],
      );

      final stats = await returnRefundStats();
      expect(stats.$1, 0);
      expect(stats.$2, 0);
      expect(await returnTxnCount(), 1);
    });

    test('M) repeated getEntries() is stable', () async {
      await seedInvoice(total: 100, cashPaid: 50, debtAmount: 50);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 5)],
      );

      final first = await returnRefundStats();
      final second = await returnRefundStats();
      expect(second.$1, first.$1);
      expect(second.$2, closeTo(first.$2, 0.001));
    });

    test('N) mixed cash/card/debt return cash ledger 15 not 25', () async {
      await seedInvoice(
        total: 100,
        cashPaid: 30,
        cardPaid: 20,
        debtAmount: 50,
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 5)],
      );

      expect(await absReturnTxnTotal(), closeTo(25, 0.001));
      final stats = await returnRefundStats();
      expect(stats.$2, closeTo(15, 0.001));
      expect(stats.$2, isNot(closeTo(25, 0.001)));
    });

    test('O) row-sum matches invoice cash pool within 0.001', () async {
      await seedInvoice(total: 100, cashPaid: 50, debtAmount: 50);
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 2)],
      );
      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 3)],
      );

      final page = await ledger.getEntries(ledgerFilter);
      final rows = page.entries
          .where((e) => e.eventType == CashLedgerEventType.returnRefund)
          .toList();
      final rowSum = rows.fold<double>(0, (sum, e) => sum + e.amount);
      expect(rowSum, closeTo(25, 0.001));
      expect(await returnCreditTotal(), closeTo(25, 0.001));
    });

    test('P) B12 credit cap clip uses actual RETURN total not theoretical',
        () async {
      await seedInvoice(total: 100, cashPaid: 50, debtAmount: 50);

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 8)],
      );

      expect(await returnCreditTotal(), closeTo(40, 0.001));
      expect(await absReturnTxnTotal(), closeTo(40, 0.001));
      final afterFirst = await returnRefundStats();
      expect(afterFirst.$2, closeTo(40, 0.001));

      await partialService.processPartialReturn(
        saleInvoiceId: invoiceId,
        returnedByUserId: returnedByUserId,
        lines: [returnLine(quantity: 2)],
      );

      final returnRows = await (db.select(db.customerTransactions)
            ..where((t) => t.type.equals('RETURN'))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      expect(returnRows.length, 2);
      expect(returnRows[0].amount.abs(), closeTo(40, 0.001));
      expect(returnRows[1].amount.abs(), closeTo(10, 0.001));

      expect(await returnCreditTotal(), closeTo(50, 0.001));
      expect(await absReturnTxnTotal(), closeTo(50, 0.001));

      final afterSecond = await returnRefundStats();
      expect(afterSecond.$2, closeTo(50, 0.001));
      expect(afterSecond.$2 - afterFirst.$2, closeTo(10, 0.001));

      final page = await ledger.getEntries(ledgerFilter);
      final ledgerRows = page.entries
          .where((e) => e.eventType == CashLedgerEventType.returnRefund)
          .toList();
      expect(ledgerRows.length, 2);
      final ledgerSum =
          ledgerRows.fold<double>(0, (sum, e) => sum + e.amount);
      expect(ledgerSum, closeTo(50, 0.001));
      expect(ledgerSum, isNot(closeTo(100, 0.001)));
    });
  });
}
