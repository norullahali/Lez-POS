import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int supplierId;
  late int productId;
  late int invoice1Id;
  late int invoice2Id;
  late int purchaseItem1Id;
  late int purchaseItem2Id;

  setUp(() async {
    db = AppDatabase.test();
    supplierId = await db.into(db.suppliers).insert(
          const SuppliersCompanion(name: Value('Test Supplier')),
        );
    productId = await db.into(db.products).insert(
          const ProductsCompanion(name: Value('Widget')),
        );
    invoice1Id = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion(
            supplierId: Value(supplierId),
            purchaseDate: Value(DateTime(2026, 1, 1)),
          ),
        );
    invoice2Id = await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion(
            supplierId: Value(supplierId),
            purchaseDate: Value(DateTime(2026, 1, 2)),
          ),
        );
    purchaseItem1Id = await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion(
            invoiceId: Value(invoice1Id),
            productId: Value(productId),
            quantity: const Value(10),
            unitCost: const Value(5),
            total: const Value(50),
          ),
        );
    purchaseItem2Id = await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion(
            invoiceId: Value(invoice2Id),
            productId: Value(productId),
            quantity: const Value(15),
            unitCost: const Value(5),
            total: const Value(75),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  SupplierReturnsCompanion supplierReturnHeader({int? purchaseInvoiceId}) {
    return SupplierReturnsCompanion(
      supplierId: Value(supplierId),
      purchaseInvoiceId: purchaseInvoiceId != null
          ? Value(purchaseInvoiceId)
          : const Value.absent(),
      returnNumber: Value('SR-${DateTime.now().microsecondsSinceEpoch}'),
    );
  }

  Map<String, dynamic> supplierReturnItemPayload({
    required int productId,
    int? purchaseItemId,
    double qty = 1,
  }) {
    return {
      if (purchaseItemId != null) 'purchaseItemId': purchaseItemId,
      'productId': productId,
      'productName': 'Widget',
      'qty': qty,
      'cost': 5.0,
    };
  }

  Future<void> seedProductStock(double qty) async {
    await (db.update(db.products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(currentStock: Value(qty)),
    );
  }

  Future<void> insertLinkedReturn({
    required int purchaseInvoiceId,
    required int? purchaseItemId,
    required double qty,
  }) async {
    final returnId = await db.into(db.supplierReturns).insert(
          SupplierReturnsCompanion(
            supplierId: Value(supplierId),
            purchaseInvoiceId: Value(purchaseInvoiceId),
            returnNumber: Value('SR-${DateTime.now().microsecondsSinceEpoch}'),
            total: Value(qty * 5),
          ),
        );
    await db.into(db.supplierReturnItems).insert(
          SupplierReturnItemsCompanion(
            returnId: Value(returnId),
            purchaseItemId: purchaseItemId != null
                ? Value(purchaseItemId)
                : const Value.absent(),
            productId: Value(productId),
            productName: const Value('Widget'),
            quantity: Value(qty),
            unitCost: const Value(5),
            total: Value(qty * 5),
          ),
        );
  }

  group('getReturnableQuantityForPurchaseItem', () {
    test('A) no prior linked returns -> full purchased quantity', () async {
      final returnable = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      expect(returnable, 10);
    });

    test('B) one linked return reduces returnable quantity', () async {
      await insertLinkedReturn(
        purchaseInvoiceId: invoice1Id,
        purchaseItemId: purchaseItem1Id,
        qty: 3,
      );
      final returnable = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      expect(returnable, 7);
    });

    test('C) multiple linked returns accumulate', () async {
      await insertLinkedReturn(
        purchaseInvoiceId: invoice1Id,
        purchaseItemId: purchaseItem1Id,
        qty: 3,
      );
      await insertLinkedReturn(
        purchaseInvoiceId: invoice1Id,
        purchaseItemId: purchaseItem1Id,
        qty: 2,
      );
      final returnable = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      expect(returnable, 5);
    });

    test('D) legacy null purchaseItemId does not reduce line returnable',
        () async {
      await insertLinkedReturn(
        purchaseInvoiceId: invoice1Id,
        purchaseItemId: null,
        qty: 8,
      );
      final returnable = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      expect(returnable, 10);
    });

    test('E) same product on different purchase item is isolated', () async {
      await insertLinkedReturn(
        purchaseInvoiceId: invoice1Id,
        purchaseItemId: purchaseItem1Id,
        qty: 3,
      );
      final line1 = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      final line2 = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem2Id);
      expect(line1, 7);
      expect(line2, 15);
    });

    test('F) clamps at zero when returns exceed purchased quantity', () async {
      await insertLinkedReturn(
        purchaseInvoiceId: invoice1Id,
        purchaseItemId: purchaseItem1Id,
        qty: 12,
      );
      final returnable = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      expect(returnable, 0);
    });

    test('G) unknown purchase item id returns 0.0', () async {
      final returnable =
          await db.returnsDao.getReturnableQuantityForPurchaseItem(999999);
      expect(returnable, 0.0);
    });
  });

  group('saveSupplierReturn structural validation', () {
    test(
        'A) linked purchaseItemId without header purchaseInvoiceId is rejected',
        () async {
      await expectLater(
        db.returnsDao.saveSupplierReturn(
          header: supplierReturnHeader(),
          items: [
            supplierReturnItemPayload(
              productId: productId,
              purchaseItemId: purchaseItem1Id,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('B) purchaseItemId from a different purchase invoice is rejected',
        () async {
      await expectLater(
        db.returnsDao.saveSupplierReturn(
          header: supplierReturnHeader(purchaseInvoiceId: invoice2Id),
          items: [
            supplierReturnItemPayload(
              productId: productId,
              purchaseItemId: purchaseItem1Id,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('C) purchaseItemId product mismatch is rejected', () async {
      final otherProductId = await db.into(db.products).insert(
            const ProductsCompanion(
              name: Value('Other Widget'),
              barcode: Value('OTHER-WIDGET-TEST'),
            ),
          );

      await expectLater(
        db.returnsDao.saveSupplierReturn(
          header: supplierReturnHeader(purchaseInvoiceId: invoice1Id),
          items: [
            supplierReturnItemPayload(
              productId: otherProductId,
              purchaseItemId: purchaseItem1Id,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('D) valid purchase linkage passes structural validation', () async {
      await seedProductStock(5);

      final returnId = await db.returnsDao.saveSupplierReturn(
        header: supplierReturnHeader(purchaseInvoiceId: invoice1Id),
        items: [
          supplierReturnItemPayload(
            productId: productId,
            purchaseItemId: purchaseItem1Id,
            qty: 2,
          ),
        ],
      );

      expect(returnId, greaterThan(0));

      final lines = await db.returnsDao.getSupplierReturnItems(returnId);
      expect(lines, hasLength(1));
      expect(lines.single.purchaseItemId, purchaseItem1Id);

      final returnable = await db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItem1Id);
      expect(returnable, 8);
    });
  });
}
