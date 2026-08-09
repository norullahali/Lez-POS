// lib/features/returns/repositories/supplier_return_read_repository.dart

import '../../../core/constants/movement_types.dart';
import '../../../core/database/app_database.dart';
import '../models/supplier_return_draft_models.dart';

class SupplierReturnReadRepository {
  SupplierReturnReadRepository(this._db);

  final AppDatabase _db;

  /// Eligible purchases: exists, has supplier, supplier row exists, not cancelled.
  Future<List<SupplierReturnPurchaseOption>> getEligiblePurchases() async {
    final invoices = await _db.purchasesDao.getAllInvoices();
    final result = <SupplierReturnPurchaseOption>[];

    for (final inv in invoices) {
      final supplierId = inv.supplierId;
      if (supplierId == null) continue;
      if (inv.status == PurchaseStatus.cancelled.code) continue;

      final supplier = await _db.suppliersDao.getSupplierById(supplierId);
      if (supplier == null) continue;

      result.add(
        SupplierReturnPurchaseOption(
          purchaseInvoiceId: inv.id,
          supplierId: supplierId,
          supplierName: supplier.name,
          invoiceNumber: inv.invoiceNumber,
          purchaseDate: inv.purchaseDate,
          totalAmount: inv.total,
          status: inv.status,
        ),
      );
    }

    return result;
  }

  /// Loads draft lines using SR.1 returnable quantity contract per purchase item.
  Future<List<SupplierReturnDraftLine>> loadDraftLines(int invoiceId) async {
    final items = await _db.purchasesDao.getItemsForInvoice(invoiceId);
    final lines = <SupplierReturnDraftLine>[];

    for (final item in items) {
      final returnable =
          await _db.returnsDao.getReturnableQuantityForPurchaseItem(item.id);
      final purchased = item.quantity;
      var alreadyReturned = purchased - returnable;
      if (alreadyReturned < 0) alreadyReturned = 0;

      final product = await (_db.select(_db.products)
            ..where((p) => p.id.equals(item.productId)))
          .getSingleOrNull();

      lines.add(
        SupplierReturnDraftLine(
          purchaseItemId: item.id,
          productId: item.productId,
          productName: product?.name ?? 'منتج #${item.productId}',
          purchasedQty: purchased,
          alreadyReturnedQty: alreadyReturned,
          returnableQty: returnable,
          unitCost: item.unitCost,
        ),
      );
    }

    return lines;
  }
}
