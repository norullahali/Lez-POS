import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_refund_settlement_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';

void main() {
  late AppDatabase db;
  late SupplierRefundSettlementService settlementService;
  late SupplierReturnService returnService;
  late int supplierId;
  late int productId;
  late int purchaseItemId;
  late int invoiceId;

  setUp(() async {
    db = AppDatabase.test();
    settlementService = SupplierRefundSettlementService(db);
    returnService = SupplierReturnService(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('Settlement Supplier')),
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

  group('SR.3.3 Step 1 supplier refund settlement', () {
    test('A) full credit settlement', () async {
      await seedCredit20();
      final before = await balance();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 20,
      );

      expect(await balance(), 0);
      expect(await refundTxnCount(), 1);
      final txn = (await db.supplierAccountsDao.getHistory(supplierId))
          .firstWhere((t) => t.type == 'REFUND');
      expect(txn.amount, 20);
      expect(before, -20);
    });

    test('B) partial credit settlement', () async {
      await seedCredit20();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 10,
      );

      expect(await balance(), -10);
      expect(await refundTxnCount(), 1);
    });

    test('C) over-settlement rejected', () async {
      await seedCredit20();
      final before = await balance();

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
    });

    test('D) zero amount rejected', () async {
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
    });

    test('E) negative amount rejected', () async {
      await seedCredit20();

      await expectLater(
        settlementService.settleCredit(
          supplierId: supplierId,
          amount: -5,
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
    });

    test('F) no credit at zero balance rejected', () async {
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
    });

    test('G) positive payable rejected', () async {
      expect(await balance(), 50);

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
    });

    test('H) supplier not found', () async {
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
    });

    test('I) return-linked settlement stores referenceId', () async {
      final returnId = await postReturnCredit20();

      await settlementService.settleCredit(
        supplierId: supplierId,
        amount: 10,
        returnId: returnId,
      );

      final txn = (await db.supplierAccountsDao.getHistory(supplierId))
          .firstWhere((t) => t.type == 'REFUND');
      expect(txn.referenceId, returnId);
      expect(txn.amount, 10);
    });

    test('J) return supplier mismatch rejected', () async {
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
    });

    test('K) missing return rejected', () async {
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
    });

    test('L) processPayment still rejects negative balance misuse', () async {
      await seedCredit20();

      await expectLater(
        SupplierAccountService(db).processPayment(
          supplierId: supplierId,
          amount: 10,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('M) goods return regression unchanged', () async {
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
      expect(await returnTxnCount(), 1);
      expect(await refundTxnCount(), 0);

      final returnTxn = (await db.supplierAccountsDao.getHistory(supplierId))
          .firstWhere((t) => t.type == 'RETURN');
      expect(returnTxn.amount, -20);
    });
  });
}
