import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
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
  late SupplierRefundSettlementService settlementService;
  late SupplierReturnService returnService;
  late FinancialLedgerRepository ledger;
  late int supplierId;
  late int productId;
  late int purchaseItemId;
  late int invoiceId;

  const ledgerFilter = CashLedgerFilter(
    page: 0,
    pageSize: 1000,
    dateFilter: ReportFilterModel(preset: ReportDatePreset.thisYear),
  );

  setUp(() async {
    db = AppDatabase.test();
    settlementService = SupplierRefundSettlementService(db);
    returnService = SupplierReturnService(db);
    ledger = FinancialLedgerRepository(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('Ledger Supplier')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(name: Value('Part')),
        );

    invoiceId = await db.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(supplierId),
        purchaseDate: Value(DateTime(2026, 3, 1)),
        total: const Value(50),
        paidAmount: const Value(0),
        debtAmount: const Value(50),
      ),
      items: [
        {'productId': productId, 'qty': 10.0, 'cost': 5.0},
      ],
    );

    final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
    purchaseItemId = items.single.id;
  });

  tearDown(() async {
    await db.close();
  });

  Future<double> balance() => db.supplierAccountsDao.getBalance(supplierId);

  Future<int> refundTxnCount() async =>
      (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('REFUND')))
              .get())
          .length;

  Future<int> activityLogCount() async =>
      (await db.select(db.logsTable).get()).length;

  Future<List<CashLedgerEvent>> supplierRefundLedgerEvents() async {
    final page = await ledger.getEntries(ledgerFilter);
    return page.entries
        .where((e) => e.eventType == CashLedgerEventType.supplierRefund)
        .toList();
  }

  Future<int> returnTxnCount() async =>
      (await (db.select(db.supplierTransactions)
                ..where((t) => t.type.equals('RETURN')))
              .get())
          .length;

  Future<void> seedCredit20() async {
    await SupplierAccountService(db).processPayment(
      supplierId: supplierId,
      amount: 50,
    );
    await returnService.postPurchaseLinkedReturn(
      SupplierReturnPostingInput(
        supplierId: supplierId,
        purchaseInvoiceId: invoiceId,
        lines: [
          SupplierReturnPostingLine(
            purchaseItemId: purchaseItemId,
            quantity: 4,
          ),
        ],
      ),
    );
    expect(await balance(), -20);
  }

  Future<int> postReturnCredit20() async {
    await seedCredit20();
    final returns = await db.select(db.supplierReturns).get();
    return returns.single.id;
  }

  group('SR.3.3 Step 2 supplier refund cash ledger', () {
    test('A) full credit refund creates one REFUND and one ledger inflow',
        () async {
      await seedCredit20();
      final summaryBefore = await ledger.getSummary(ledgerFilter);

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 20,
      );

      expect(await balance(), 0);
      expect(await refundTxnCount(), 1);

      final events = await supplierRefundLedgerEvents();
      expect(events.length, 1);
      expect(events.single.amount, 20);
      expect(events.single.isInflow, isTrue);
      expect(events.single.supplierId, supplierId);
      expect(events.single.referenceType, 'supplier_transaction');

      final summaryAfter = await ledger.getSummary(ledgerFilter);
      expect(summaryAfter.totalInflow, summaryBefore.totalInflow + 20);
    });

    test('B) partial credit refund creates one REFUND and one ledger event',
        () async {
      await seedCredit20();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 10,
      );

      expect(await balance(), -10);
      expect(await refundTxnCount(), 1);
      expect((await supplierRefundLedgerEvents()).length, 1);
    });

    test('C) over-refund rejected leaves zero REFUND and zero ledger events',
        () async {
      await seedCredit20();
      final before = await balance();
      final ledgerBefore = (await supplierRefundLedgerEvents()).length;

      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: 30,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.amountExceedsCredit,
          ),
        ),
      );

      expect(await balance(), before);
      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, ledgerBefore);
    });

    test('D) no supplier credit rejected with zero ledger events', () async {
      await SupplierAccountService(db).processPayment(
        supplierId: supplierId,
        amount: 50,
      );
      expect(await balance(), 0);

      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: 10,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.noSupplierCredit,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
    });

    test('E) invalid amount rejected with zero ledger events', () async {
      await seedCredit20();

      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: 0,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.invalidAmount,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
    });

    test('F) missing supplier rejected with zero ledger events', () async {
      await expectLater(
        settlementService.settleCredit(
          supplierId: 999999,
          amount: 10,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.supplierNotFound,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
    });

    test('G) return supplier mismatch rejected with zero ledger events',
        () async {
      final returnId = await postReturnCredit20();
      final otherSupplierId = await db.into(db.suppliers).insert(
            const SuppliersCompanion(name: Value('Other Supplier')),
          );

      await expectLater(
        settlementService.settleCredit(
          supplierId: otherSupplierId,
          amount: 10,
          returnId: returnId,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.returnSupplierMismatch,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
    });

    test('H) missing return rejected with zero ledger events', () async {
      await seedCredit20();

      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: 10,
          returnId: 999999,
        ),
        throwsA(
          isA<SupplierRefundSettlementException>().having(
            (e) => e.code,
            'code',
            SupplierRefundSettlementFailure.returnNotFound,
          ),
        ),
      );

      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
    });

    test('I) goods RETURN alone creates no Cash Ledger event', () async {
      await SupplierAccountService(db).processPayment(
        supplierId: supplierId,
        amount: 50,
      );

      final before = await ledger.getEntries(ledgerFilter);

      await returnService.postPurchaseLinkedReturn(
        SupplierReturnPostingInput(
          supplierId: supplierId,
          purchaseInvoiceId: invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 4,
            ),
          ],
        ),
      );

      final after = await ledger.getEntries(ledgerFilter);
      expect(after.entries.length, before.entries.length);
      expect(await returnTxnCount(), 1);
      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
    });

    test('J) cash refund creates only one SUPPLIER_REFUND ledger event',
        () async {
      await seedCredit20();
      final beforeCount =
          (await ledger.getEntries(ledgerFilter)).entries.length;

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 20,
      );

      final after = await ledger.getEntries(ledgerFilter);
      expect(after.entries.length, beforeCount + 1);
      expect((await supplierRefundLedgerEvents()).length, 1);
    });

    test('K) post-refund failure rolls back REFUND and ledger visibility',
        () async {
      await seedCredit20();
      final logsBefore = await activityLogCount();
      final failingService = SupplierRefundSettlementService(
        db,
        postRefundHook: () async {
          throw Exception('forced cash ledger companion failure');
        },
      );

      await expectLater(
        failingService.settleCredit(
          supplierId: supplierId,
          amount: 20,
        ),
        throwsA(isA<SupplierRefundSettlementException>()),
      );

      expect(await balance(), -20);
      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
      expect(await activityLogCount(), logsBefore);
    });

    test('L) accounting failure rolls back with zero ledger events', () async {
      await seedCredit20();
      final failingService = SupplierRefundSettlementService(
        db,
        refundInTransactionOverride: ({
          required int supplierId,
          required double amount,
          int? returnId,
          String? note,
        }) async {
          throw Exception('forced accounting failure');
        },
      );

      await expectLater(
        failingService.settleCredit(
          supplierId: supplierId,
          amount: 20,
        ),
        throwsA(isA<SupplierRefundSettlementException>()),
      );

      expect(await balance(), -20);
      expect(await refundTxnCount(), 0);
      expect((await supplierRefundLedgerEvents()).length, 0);
    });

    test(
        'M) one service invocation creates exactly one REFUND and one ledger event',
        () async {
      await seedCredit20();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 15,
      );

      expect(await refundTxnCount(), 1);
      expect((await supplierRefundLedgerEvents()).length, 1);
    });

    test('return-linked refund exposes purchase invoice on ledger event',
        () async {
      final returnId = await postReturnCredit20();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 10,
        returnId: returnId,
      );

      final event = (await supplierRefundLedgerEvents()).single;
      expect(event.invoiceId, invoiceId);
      expect(event.supplierId, supplierId);
    });
  });
}
