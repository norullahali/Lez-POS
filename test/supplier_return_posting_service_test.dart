import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/constants/movement_types.dart';
import 'package:lez_pos/core/database/app_database.dart';
import 'package:lez_pos/core/services/supplier_return_service.dart';
import 'package:lez_pos/features/financial/models/cash_ledger_filter.dart';
import 'package:lez_pos/features/financial/repositories/financial_ledger_repository.dart';

void main() {
  late AppDatabase db;
  late SupplierReturnService service;
  late int supplierId;
  late int otherSupplierId;
  late int productId;
  late int product2Id;
  late int purchaseItem1Id;
  late int purchaseItem2Id;
  late int invoiceId;

  setUp(() async {
    db = AppDatabase.test();
    service = SupplierReturnService(db);

    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('Test Supplier')),
        );
    otherSupplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('Other Supplier')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(name: Value('Widget')),
        );
    product2Id = await db.into(db.products).insert(
          const ProductsCompanion(
            name: Value('Gadget'),
            barcode: Value('GADGET-SR2'),
          ),
        );

    invoiceId = await db.purchasesDao.savePurchaseInvoice(
      header: PurchaseInvoicesCompanion(
        supplierId: Value(supplierId),
        purchaseDate: Value(DateTime(2026, 1, 1)),
        total: const Value(100),
        paidAmount: const Value(0),
        debtAmount: const Value(100),
        invoiceNumber: const Value('PI-001'),
      ),
      items: [
        {'productId': productId, 'qty': 10.0, 'cost': 5.0},
        {'productId': product2Id, 'qty': 10.0, 'cost': 5.0},
      ],
    );

    final items = await db.purchasesDao.getItemsForInvoice(invoiceId);
    purchaseItem1Id = items.firstWhere((i) => i.productId == productId).id;
    purchaseItem2Id = items.firstWhere((i) => i.productId == product2Id).id;
  });

  tearDown(() async {
    await db.close();
  });

  SupplierReturnPostingInput postingInput({
    int? supplier,
    int? purchaseInvoice,
    List<SupplierReturnPostingLine>? lines,
  }) {
    return SupplierReturnPostingInput(
      supplierId: supplier ?? supplierId,
      purchaseInvoiceId: purchaseInvoice ?? invoiceId,
      lines: lines ??
          [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItem1Id,
              quantity: 2,
            ),
          ],
    );
  }

  Future<double> supplierBalance() =>
      db.supplierAccountsDao.getBalance(supplierId);

  Future<int> supplierReturnCount() async {
    final rows = await db.select(db.supplierReturns).get();
    return rows.length;
  }

  Future<int> returnOutLedgerCount() async {
    final rows = await (db.select(db.stockLedger)
          ..where(
              (l) => l.movementType.equals(StockMovementType.returnOut.code)))
        .get();
    return rows.length;
  }

  Future<int> supplierReturnTxnCount() async {
    final rows = await (db.select(db.supplierTransactions)
          ..where((t) => t.type.equals('RETURN')))
        .get();
    return rows.length;
  }

  Future<double> productStock(int id) => db.stockDao.getStock(id);

  group('SupplierReturnService.postPurchaseLinkedReturn', () {
    test('A) valid credit purchase return posts stock and supplier liability',
        () async {
      final balanceBefore = await supplierBalance();
      expect(balanceBefore, 100);

      final stockBefore = await productStock(productId);
      expect(stockBefore, 10);

      final returnId = await service.postPurchaseLinkedReturn(postingInput());

      expect(returnId, greaterThan(0));
      expect(await supplierReturnCount(), 1);

      final items = await db.returnsDao.getSupplierReturnItems(returnId);
      expect(items, hasLength(1));
      expect(items.single.purchaseItemId, purchaseItem1Id);
      expect(items.single.quantity, 2);
      expect(items.single.unitCost, 5);
      expect(items.single.total, 10);

      expect(await productStock(productId), stockBefore - 2);
      expect(await returnOutLedgerCount(), 1);
      expect(await supplierReturnTxnCount(), 1);
      expect(await supplierBalance(), 90);

      final txns = await db.supplierAccountsDao.getHistory(supplierId);
      final returnTxn = txns.firstWhere((t) => t.type == 'RETURN');
      expect(returnTxn.amount, -10);
      expect(returnTxn.referenceId, returnId);
    });

    test('B) requestedQty > returnableQty rejects with no side effects',
        () async {
      await expectLater(
        service.postPurchaseLinkedReturn(
          postingInput(
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: purchaseItem1Id,
                quantity: 11,
              ),
            ],
          ),
        ),
        throwsA(
          predicate(
            (e) =>
                e is SupplierReturnPostingException &&
                e.code ==
                    SupplierReturnPostingFailure.quantityExceedsReturnable,
          ),
        ),
      );

      expect(await supplierReturnCount(), 0);
      expect(await returnOutLedgerCount(), 0);
      expect(await supplierReturnTxnCount(), 0);
      expect(await supplierBalance(), 100);
    });

    test('C) only remaining returnable quantity can post after prior return',
        () async {
      await service.postPurchaseLinkedReturn(
        postingInput(
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItem1Id,
              quantity: 7,
            ),
          ],
        ),
      );

      await service.postPurchaseLinkedReturn(
        postingInput(
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItem1Id,
              quantity: 3,
            ),
          ],
        ),
      );

      await expectLater(
        service.postPurchaseLinkedReturn(
          postingInput(
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: purchaseItem1Id,
                quantity: 1,
              ),
            ],
          ),
        ),
        throwsA(isA<SupplierReturnPostingException>()),
      );

      expect(await supplierReturnCount(), 2);
      expect(await returnOutLedgerCount(), 2);
    });

    test('D) wrong supplier for purchase is rejected atomically', () async {
      await expectLater(
        service.postPurchaseLinkedReturn(
          postingInput(supplier: otherSupplierId),
        ),
        throwsA(
          predicate(
            (e) =>
                e is SupplierReturnPostingException &&
                e.code == SupplierReturnPostingFailure.supplierMismatch,
          ),
        ),
      );

      expect(await supplierReturnCount(), 0);
      expect(await returnOutLedgerCount(), 0);
      expect(await supplierReturnTxnCount(), 0);
    });

    test('E) purchase item from another purchase is rejected atomically',
        () async {
      final otherInvoiceId = await db.purchasesDao.savePurchaseInvoice(
        header: PurchaseInvoicesCompanion(
          supplierId: Value(supplierId),
          purchaseDate: Value(DateTime(2026, 2, 1)),
          total: const Value(50),
          paidAmount: const Value(50),
          debtAmount: const Value(0),
        ),
        items: [
          {'productId': productId, 'qty': 5.0, 'cost': 5.0},
        ],
      );
      final otherItems =
          await db.purchasesDao.getItemsForInvoice(otherInvoiceId);
      final foreignItemId = otherItems.single.id;

      await expectLater(
        service.postPurchaseLinkedReturn(
          postingInput(
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: foreignItemId,
                quantity: 1,
              ),
            ],
          ),
        ),
        throwsA(
          predicate(
            (e) =>
                e is SupplierReturnPostingException &&
                e.code ==
                    SupplierReturnPostingFailure.purchaseItemInvoiceMismatch,
          ),
        ),
      );

      expect(await supplierReturnCount(), 0);
      expect(await returnOutLedgerCount(), 0);
    });

    test('F) duplicate purchaseItemId lines aggregate before validation',
        () async {
      await expectLater(
        service.postPurchaseLinkedReturn(
          postingInput(
            lines: [
              SupplierReturnPostingLine(
                purchaseItemId: purchaseItem1Id,
                quantity: 6,
              ),
              SupplierReturnPostingLine(
                purchaseItemId: purchaseItem1Id,
                quantity: 6,
              ),
            ],
          ),
        ),
        throwsA(
          predicate(
            (e) =>
                e is SupplierReturnPostingException &&
                e.code ==
                    SupplierReturnPostingFailure.quantityExceedsReturnable,
          ),
        ),
      );

      expect(await supplierReturnCount(), 0);
    });

    test('G) stock failure rolls back return and supplier accounting',
        () async {
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(currentStock: Value(0)));

      await expectLater(
        service.postPurchaseLinkedReturn(postingInput()),
        throwsA(
          predicate(
            (e) =>
                e is SupplierReturnPostingException &&
                e.code == SupplierReturnPostingFailure.stockInsufficient,
          ),
        ),
      );

      expect(await supplierReturnCount(), 0);
      expect(await returnOutLedgerCount(), 0);
      expect(await supplierReturnTxnCount(), 0);
      expect(await supplierBalance(), 100);
    });

    test('H) supplier accounting failure rolls back stock and return',
        () async {
      final failingService = SupplierReturnService.withAccountingPoster(
        db,
        accountingPoster: ({
          required int supplierId,
          required double amount,
          required int returnId,
          String note = '',
        }) async {
          throw Exception('forced accounting failure');
        },
      );

      final stockBefore = await productStock(productId);

      await expectLater(
        failingService.postPurchaseLinkedReturn(postingInput()),
        throwsA(
          predicate(
            (e) =>
                e is SupplierReturnPostingException &&
                e.code ==
                    SupplierReturnPostingFailure.supplierAccountingFailure,
          ),
        ),
      );

      expect(await supplierReturnCount(), 0);
      expect(await returnOutLedgerCount(), 0);
      expect(await supplierReturnTxnCount(), 0);
      expect(await productStock(productId), stockBefore);
      expect(await supplierBalance(), 100);
    });

    test(
        'I) multi-item return posts each stock movement once with correct total',
        () async {
      final returnId = await service.postPurchaseLinkedReturn(
        postingInput(
          lines: [
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItem1Id,
              quantity: 2,
            ),
            SupplierReturnPostingLine(
              purchaseItemId: purchaseItem2Id,
              quantity: 4,
            ),
          ],
        ),
      );

      final items = await db.returnsDao.getSupplierReturnItems(returnId);
      expect(items, hasLength(2));
      expect(await returnOutLedgerCount(), 2);

      final expectedTotal = (2 * 5) + (4 * 5);
      final header = await (db.select(db.supplierReturns)
            ..where((r) => r.id.equals(returnId)))
          .getSingle();
      expect(header.total, expectedTotal);

      final txns = await db.supplierAccountsDao.getHistory(supplierId);
      final returnTxn = txns.firstWhere((t) => t.type == 'RETURN');
      expect(returnTxn.amount, -expectedTotal);
      expect(await supplierBalance(), 100 - expectedTotal);
    });

    test('J) no cash ledger event is created for goods return alone', () async {
      final ledger = FinancialLedgerRepository(db);
      final before = await ledger.getEntries(
        const CashLedgerFilter(page: 0, pageSize: 1000),
      );

      await service.postPurchaseLinkedReturn(postingInput());

      final after = await ledger.getEntries(
        const CashLedgerFilter(page: 0, pageSize: 1000),
      );
      expect(after.entries.length, before.entries.length);
      expect(await supplierReturnTxnCount(), 1);
    });
  });

  group('aggregatePostingLines', () {
    test('sums duplicate purchaseItemId quantities', () {
      final aggregated = aggregatePostingLines(const [
        SupplierReturnPostingLine(purchaseItemId: 1, quantity: 3),
        SupplierReturnPostingLine(purchaseItemId: 1, quantity: 3),
        SupplierReturnPostingLine(purchaseItemId: 2, quantity: 1),
      ]);
      expect(aggregated[1], 6);
      expect(aggregated[2], 1);
    });
  });
}
