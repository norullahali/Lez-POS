import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/database/daos/returns_dao.dart';
import 'package:lez_pos/core/services/supplier_account_service.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';

void main() {
  late AppDatabase db;
  late SupplierReturnService service;
  late int supplierId;
  late int productId;
  late int purchaseItemId;
  late int invoiceId;

  setUp(() async {
    db = AppDatabase.test();
    service = SupplierReturnService(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('Hardening Supplier')),
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

  Future<int> returnCount() async =>
      (await db.select(db.supplierReturns).get()).length;

  Future<int> returnOutCount() async => (await (db.select(db.stockLedger)
        ..where((l) => l.movementType.equals(StockMovementType.returnOut.code)))
      .get())
      .length;

  Future<int> returnTxnCount() async => (await (db.select(db.supplierTransactions)
        ..where((t) => t.type.equals('RETURN')))
      .get())
      .length;

  group('F-01 DAO bypass guard', () {
    test('A) direct saveSupplierReturn purchase-linked path is rejected',
        () async {
      final stockBefore = await db.stockDao.getStock(productId);
      final balanceBefore = await db.supplierAccountsDao.getBalance(supplierId);

      await expectLater(
        db.returnsDao.saveSupplierReturn(
          header: SupplierReturnsCompanion(
            supplierId: Value(supplierId),
            purchaseInvoiceId: Value(invoiceId),
            returnNumber: Value('SR-BYPASS-${DateTime.now().microsecondsSinceEpoch}'),
          ),
          items: [
            {
              'purchaseItemId': purchaseItemId,
              'productId': productId,
              'productName': 'Part',
              'qty': 2.0,
              'cost': 5.0,
            },
          ],
        ),
        throwsA(isA<SupplierReturnDirectPostingForbiddenException>()),
      );

      expect(await returnCount(), 0);
      expect(await returnOutCount(), 0);
      expect(await returnTxnCount(), 0);
      expect(await db.stockDao.getStock(productId), stockBefore);
      expect(await db.supplierAccountsDao.getBalance(supplierId), balanceBefore);
    });

    test('B) canonical service path succeeds for same purchase-linked data',
        () async {
      final returnId = await service.postPurchaseLinkedReturn(
        SupplierReturnPostingInput(
          supplierId: supplierId,
          purchaseInvoiceId: invoiceId,
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItemId,
              quantity: 2,
            ),
          ],
        ),
      );

      expect(returnId, greaterThan(0));
      expect(await returnCount(), 1);
      expect(await returnOutCount(), 1);
      expect(await returnTxnCount(), 1);
      expect(await db.supplierAccountsDao.getBalance(supplierId), 40);
    });

    test('C) manual unlinked saveSupplierReturn remains supported', () async {
      await (db.update(db.products)..where((p) => p.id.equals(productId))).write(
        const ProductsCompanion(currentStock: Value(5)),
      );

      final returnId = await db.returnsDao.saveSupplierReturn(
        header: SupplierReturnsCompanion(
          supplierId: Value(supplierId),
          returnNumber: Value('SR-MANUAL-${DateTime.now().microsecondsSinceEpoch}'),
        ),
        items: [
          {
            'productId': productId,
            'productName': 'Part',
            'qty': 1.0,
            'cost': 5.0,
          },
        ],
      );

      expect(returnId, greaterThan(0));
      final lines = await db.returnsDao.getSupplierReturnItems(returnId);
      expect(lines.single.purchaseItemId, equals(null));
      expect(await returnTxnCount(), 0);
    });
  });

  group('Fully-paid supplier credit semantics', () {
    test('return after full payment yields negative balance, zero cash ledger',
        () async {
      await SupplierAccountService(db).processPayment(
        supplierId: supplierId,
        amount: 50,
      );
      expect(await db.supplierAccountsDao.getBalance(supplierId), 0);

      final ledger = FinancialLedgerRepository(db);
      final cashBefore = await ledger.getEntries(
        const CashLedgerFilter(page: 0, pageSize: 1000),
      );

      await service.postPurchaseLinkedReturn(
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

      expect(await db.supplierAccountsDao.getBalance(supplierId), -20);

      final returnTxn = (await db.supplierAccountsDao.getHistory(supplierId))
          .firstWhere((t) => t.type == 'RETURN');
      expect(returnTxn.amount, -20);

      final cashAfter = await ledger.getEntries(
        const CashLedgerFilter(page: 0, pageSize: 1000),
      );
      expect(cashAfter.entries.length, cashBefore.entries.length);
    });
  });
}
