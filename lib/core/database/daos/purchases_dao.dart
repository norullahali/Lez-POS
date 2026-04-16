// lib/core/database/daos/purchases_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/purchase_invoices_table.dart';
import '../tables/purchase_items_table.dart';
import '../tables/stock_ledger_table.dart';
import '../tables/products_table.dart';
import '../../constants/movement_types.dart';

part 'purchases_dao.g.dart';

@DriftAccessor(tables: [PurchaseInvoices, PurchaseItems, StockLedger, Products])
class PurchasesDao extends DatabaseAccessor<AppDatabase> with _$PurchasesDaoMixin {
  PurchasesDao(super.db);

  // List all purchase invoices
  Future<List<PurchaseInvoice>> getAllInvoices() =>
      (select(purchaseInvoices)
        ..orderBy([(i) => OrderingTerm.desc(i.purchaseDate)]))
          .get();

  Stream<List<PurchaseInvoice>> watchAllInvoices() =>
      (select(purchaseInvoices)
        ..orderBy([(i) => OrderingTerm.desc(i.purchaseDate)]))
          .watch();

  Future<List<PurchaseInvoice>> getInvoicesByDateRange(
      DateTime from, DateTime to) =>
      (select(purchaseInvoices)
        ..where((i) => i.purchaseDate.isBetweenValues(from, to))
        ..orderBy([(i) => OrderingTerm.desc(i.purchaseDate)]))
          .get();

  Future<PurchaseInvoice?> getInvoiceById(int id) =>
      (select(purchaseInvoices)..where((i) => i.id.equals(id)))
          .getSingleOrNull();

  Future<List<PurchaseItem>> getItemsForInvoice(int invoiceId) =>
      (select(purchaseItems)
        ..where((item) => item.invoiceId.equals(invoiceId)))
          .get();

  /// Get purchases grouped by supplier within a date range
  Future<List<Map<String, dynamic>>> getPurchasesBySupplier(DateTime from, DateTime to) async {
    final rows = await customSelect(
      '''SELECT 
           s.id as supplier_id, 
           COALESCE(s.name, 'بدون مورد') as supplier_name,
           COUNT(pi.id) as invoice_count,
           COALESCE(SUM(pi.total), 0) as total_amount
         FROM purchase_invoices pi
         LEFT JOIN suppliers s ON s.id = pi.supplier_id
         WHERE pi.purchase_date >= ? AND pi.purchase_date <= ?
         GROUP BY pi.supplier_id
         ORDER BY total_amount DESC''',
      variables: [Variable(from), Variable(to)],
      readsFrom: {purchaseInvoices, db.suppliers}, // Need to refer to suppliers table on DB level
    ).get();
    return rows.map((r) => r.data).toList();
  }

  /// Save full purchase invoice: header + items + stock ledger entries in one transaction
  Future<int> savePurchaseInvoice({
    required PurchaseInvoicesCompanion header,
    required List<Map<String, dynamic>> items, // {productId, qty, cost, discount, expiry}
  }) async {
    return transaction(() async {
      final invoiceId = await into(purchaseInvoices).insert(header);

      for (final item in items) {
        final productId = item['productId'] as int;
        final qty = (item['qty'] as num).toDouble();
        final cost = (item['cost'] as num).toDouble();
        final discount = (item['discount'] as num?)?.toDouble() ?? 0.0;
        final itemTotal = (qty * cost) - discount;
        final expiryDate = item['expiryDate'] as DateTime?;

        // Insert purchase item
        final itemId = await into(purchaseItems).insert(
          PurchaseItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(productId),
            quantity: Value(qty),
            unitCost: Value(cost),
            discountAmount: Value(discount),
            total: Value(itemTotal),
            expiryDate: Value(expiryDate),
          ),
        );

        // Update cost price on product
        await (update(products)..where((p) => p.id.equals(productId))).write(
          ProductsCompanion(costPrice: Value(cost), updatedAt: Value(DateTime.now())),
        );

        // Add stock ledger entry
        await into(stockLedger).insert(
          StockLedgerCompanion(
            productId: Value(productId),
            movementType: Value(StockMovementType.purchase.code),
            referenceId: Value(itemId),
            referenceType: const Value('purchase_items'),
            quantityChange: Value(qty),
          ),
        );
      }

      // 4. Handle supplier debt if applicable
      if (header.supplierId.present && header.supplierId.value != null) {
        final supplierId = header.supplierId.value!;
        final debtAmt = header.debtAmount.present ? header.debtAmount.value : 0.0;
        
        if (debtAmt > 0) {
          await db.supplierAccountsDao.addTransaction(
             supplierId: supplierId,
             type: 'PURCHASE',
             amount: debtAmt,
             referenceId: invoiceId,
             note: 'فاتورة مشتريات #${header.invoiceNumber.present ? header.invoiceNumber.value : invoiceId}',
          );
        }
      }

      return invoiceId;
    });
  }

  Future<int> deleteInvoice(int id) =>
      (delete(purchaseInvoices)..where((i) => i.id.equals(id))).go();
}
