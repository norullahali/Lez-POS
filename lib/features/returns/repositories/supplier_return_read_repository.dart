// lib/features/returns/repositories/supplier_return_read_repository.dart

import '../../../core/constants/movement_types.dart';
import '../../../core/database/app_database.dart';
import '../models/supplier_return_draft_models.dart';
import '../models/supplier_return_history_models.dart';

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

  /// Recent supplier returns for history/list presentation (read-only).
  Future<List<SupplierReturnListItem>> listSupplierReturns({
    int limit = 100,
  }) async {
    final rows = await _db.returnsDao.listSupplierReturnsHistory(limit: limit);
    return rows.map(_mapHistoryRow).toList();
  }

  /// Read-only detail for a persisted supplier return.
  Future<SupplierReturnDetail?> getSupplierReturnDetail(int returnId) async {
    final header = await _db.returnsDao.getSupplierReturnById(returnId);
    if (header == null) return null;

    final items = await _db.returnsDao.getSupplierReturnItems(returnId);
    String? supplierName;
    if (header.supplierId != null) {
      final supplier =
          await _db.suppliersDao.getSupplierById(header.supplierId!);
      supplierName = supplier?.name;
    }

    String? purchaseInvoiceNumber;
    if (header.purchaseInvoiceId != null) {
      final invoice =
          await _db.purchasesDao.getInvoiceById(header.purchaseInvoiceId!);
      purchaseInvoiceNumber = invoice?.invoiceNumber;
    }

    return SupplierReturnDetail(
      id: header.id,
      returnNumber: header.returnNumber,
      returnDate: header.returnDate,
      total: header.total,
      reason: header.reason,
      notes: header.notes,
      supplierId: header.supplierId,
      supplierName: supplierName,
      purchaseInvoiceId: header.purchaseInvoiceId,
      purchaseInvoiceNumber: purchaseInvoiceNumber,
      lines: items
          .map(
            (item) => SupplierReturnDetailLine(
              id: item.id,
              purchaseItemId: item.purchaseItemId,
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              unitCost: item.unitCost,
              total: item.total,
            ),
          )
          .toList(),
    );
  }

  SupplierReturnListItem _mapHistoryRow(Map<String, dynamic> row) {
    return SupplierReturnListItem(
      id: row['id'] as int,
      returnNumber: row['return_number'] as String? ?? '',
      returnDate: _parseDateTime(row['return_date']),
      total: (row['total'] as num?)?.toDouble() ?? 0,
      reason: row['reason'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      supplierId: row['supplier_id'] as int?,
      supplierName: row['supplier_name'] as String?,
      purchaseInvoiceId: row['purchase_invoice_id'] as int?,
      purchaseInvoiceNumber: row['purchase_invoice_number'] as String?,
      lineCount: (row['line_count'] as num?)?.toInt() ?? 0,
    );
  }

  DateTime _parseDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.parse(value);
    throw ArgumentError('Unsupported date value: $value');
  }
}
