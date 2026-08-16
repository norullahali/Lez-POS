// lib/core/database/daos/sale_item_returns_dao.dart
//
// DAO for the sale_item_returns table.
// Contains ALL Drift Companion usage for partial returns.
// Write operations called by PartialReturnService are wrapped in that
// service's transaction so they stay atomic.

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sale_item_returns_table.dart';
import '../tables/stock_ledger_table.dart';
import '../tables/products_table.dart';
import '../tables/sales_invoices_table.dart';
import '../tables/sale_items_table.dart';
import '../../constants/movement_types.dart';

part 'sale_item_returns_dao.g.dart';

@DriftAccessor(tables: [
  SaleItemReturns,
  StockLedger,
  Products,
  SalesInvoices,
  SaleItems,
])
class SaleItemReturnsDao extends DatabaseAccessor<AppDatabase>
    with _$SaleItemReturnsDaoMixin {
  SaleItemReturnsDao(super.db);

  // -- Reads ----------------------------------------------------------------

  Future<List<SaleItemReturn>> getReturnsForSaleItem(int saleItemId) =>
      (select(saleItemReturns)
            ..where((r) => r.saleItemId.equals(saleItemId))
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
          .get();

  Future<List<SaleItemReturn>> getReturnsForInvoice(int saleInvoiceId) =>
      (select(saleItemReturns)
            ..where((r) => r.saleInvoiceId.equals(saleInvoiceId))
            ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
          .get();

  // Sum of already-returned quantity for a single sale line.
  Future<double> getReturnedQuantityForSaleItem(int saleItemId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(returned_quantity), 0.0) AS total '
      'FROM sale_item_returns WHERE sale_item_id = ?',
      variables: [Variable.withInt(saleItemId)],
      readsFrom: {saleItemReturns},
    ).getSingleOrNull();
    return (result?.data['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Per-line returned qty map for a full invoice: { saleItemId -> returnedQty }
  Future<Map<int, double>> getReturnedQuantitiesForInvoice(
      int saleInvoiceId) async {
    final rows = await customSelect(
      'SELECT sale_item_id, COALESCE(SUM(returned_quantity), 0.0) AS total '
      'FROM sale_item_returns '
      'WHERE sale_invoice_id = ? '
      'GROUP BY sale_item_id',
      variables: [Variable.withInt(saleInvoiceId)],
      readsFrom: {saleItemReturns},
    ).get();
    return {
      for (final r in rows)
        (r.data['sale_item_id'] as int): (r.data['total'] as num).toDouble(),
    };
  }

  // Original sold quantity for a sale line.
  Future<double?> getSaleItemQuantity(int saleItemId) async {
    final row = await (select(saleItems)..where((i) => i.id.equals(saleItemId)))
        .getSingleOrNull();
    return row?.quantity;
  }

  // Whether any returns exist for a given invoice.
  Future<bool> hasAnyReturns(int saleInvoiceId) async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM sale_item_returns WHERE sale_invoice_id = ?',
      variables: [Variable.withInt(saleInvoiceId)],
      readsFrom: {saleItemReturns},
    ).getSingleOrNull();
    return ((result?.data['cnt'] as num?)?.toInt() ?? 0) > 0;
  }

  // -- Writes (called from PartialReturnService inside a transaction) --------

  // Insert a single return line record. Returns the new row id.
  Future<int> insertReturnLine({
    required int saleInvoiceId,
    required int saleItemId,
    required int productId,
    required double returnedQuantity,
    required double unitPriceAtReturn,
    required double returnTotal,
    required int returnedByUserId,
    String? returnReasonNote,
  }) =>
      into(saleItemReturns).insert(
        SaleItemReturnsCompanion.insert(
          saleInvoiceId: saleInvoiceId,
          saleItemId: saleItemId,
          productId: productId,
          returnedQuantity: returnedQuantity,
          unitPriceAtReturn: unitPriceAtReturn,
          returnTotal: returnTotal,
          returnReasonNote: Value(returnReasonNote),
          returnedByUserId: returnedByUserId,
        ),
      );

  // Restore stock for a product by adding qty back.
  Future<void> restoreProductStock(int productId, double qty) => customUpdate(
        'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
        variables: [Variable.withReal(qty), Variable.withInt(productId)],
        updates: {products},
      );

  // Insert a stock_ledger entry for a partial return.
  Future<void> insertStockLedgerReturn({
    required int productId,
    required int referenceId,
    required double quantity,
    required double unitCost,
  }) =>
      into(stockLedger).insert(
        StockLedgerCompanion(
          productId: Value(productId),
          movementType: Value(StockMovementType.returnIn.code),
          referenceId: Value(referenceId),
          referenceType: const Value('sale_item_returns'),
          quantityChange: Value(quantity),
          unitCost: Value(unitCost),
        ),
      );

  // Persist updated invoice_status on the sales_invoices row.
  Future<void> setInvoiceStatus(int saleInvoiceId, String status) =>
      customUpdate(
        'UPDATE sales_invoices SET invoice_status = ? WHERE id = ?',
        variables: [
          Variable.withString(status),
          Variable.withInt(saleInvoiceId),
        ],
        updates: {salesInvoices},
      );

  /// Return metadata columns when an invoice becomes fully returned.
  Future<void> setInvoiceReturnMetadata({
    required int saleInvoiceId,
    required String note,
    required int returnedByUserId,
  }) async {
    final now = DateTime.now();
    await customUpdate(
      '''UPDATE sales_invoices
         SET return_date = ?,
             return_note = ?,
             returned_by_user_id = ?
         WHERE id = ?''',
      variables: [
        Variable.withInt(now.millisecondsSinceEpoch),
        Variable.withString(note.trim()),
        Variable.withInt(returnedByUserId),
        Variable.withInt(saleInvoiceId),
      ],
      updates: {salesInvoices},
    );
  }
}
