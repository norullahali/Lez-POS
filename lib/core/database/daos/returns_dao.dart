// lib/core/database/daos/returns_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/customer_returns_table.dart';
import '../tables/supplier_returns_table.dart';
import '../tables/stock_ledger_table.dart';
import '../../constants/invoice_lifecycle.dart';
import '../../constants/movement_types.dart';
import '../../services/stock_guard.dart';

part 'returns_dao.g.dart';

/// Thrown when [ReturnsDao.saveSupplierReturn] receives purchase linkage.
///
/// New purchase-linked returns must use
/// [SupplierReturnService.postPurchaseLinkedReturn].
class SupplierReturnDirectPostingForbiddenException implements Exception {
  const SupplierReturnDirectPostingForbiddenException([
    this.message = 'Purchase-linked supplier returns must be posted through '
        'SupplierReturnService.postPurchaseLinkedReturn().',
  ]);

  final String message;

  @override
  String toString() => message;
}

@DriftAccessor(tables: [
  CustomerReturns,
  CustomerReturnItems,
  SupplierReturns,
  SupplierReturnItems,
  StockLedger,
])
class ReturnsDao extends DatabaseAccessor<AppDatabase> with _$ReturnsDaoMixin {
  ReturnsDao(super.db);

  // --- Customer Returns ---
  Future<List<CustomerReturn>> getAllCustomerReturns() =>
      (select(customerReturns)
            ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
          .get();

  Future<List<CustomerReturnItem>> getCustomerReturnItems(int returnId) =>
      (select(customerReturnItems)..where((i) => i.returnId.equals(returnId)))
          .get();

  Future<int> saveCustomerReturn({
    required CustomerReturnsCompanion header,
    required List<Map<String, dynamic>> items,
    int? returnedByUserId,
  }) async {
    return transaction(() async {
      final returnId = await into(customerReturns).insert(header);

      String? cashierName;
      if (returnedByUserId != null) {
        final cashierRow = await customSelect(
          'SELECT full_name FROM users WHERE id = ?',
          variables: [Variable.withInt(returnedByUserId)],
          readsFrom: {attachedDatabase.usersTable},
        ).getSingleOrNull();
        cashierName = cashierRow?.data['full_name'] as String?;
      }

      final returnRow = await (select(customerReturns)
            ..where((r) => r.id.equals(returnId)))
          .getSingle();

      for (final item in items) {
        final productId = item['productId'] as int;
        final qty = (item['qty'] as num).toDouble();
        final price = (item['price'] as num).toDouble();
        final cost = (item['cost'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = qty * price;

        final stockBefore = await attachedDatabase.stockDao.getStock(productId);

        final itemId = await into(customerReturnItems).insert(
          CustomerReturnItemsCompanion(
            returnId: Value(returnId),
            productId: Value(productId),
            productName:
                Value(item['productName'] as String? ?? 'منتج #$productId'),
            quantity: Value(qty),
            unitPrice: Value(price),
            unitCost: Value(cost),
            total: Value(lineTotal),
          ),
        );

        // Stock comes BACK IN when customer returns
        await into(stockLedger).insert(
          StockLedgerCompanion(
            productId: Value(productId),
            movementType: Value(StockMovementType.returnIn.code),
            referenceId: Value(itemId),
            referenceType: const Value('customer_return_items'),
            quantityChange: Value(qty), // positive = stock back in
            unitCost: Value(cost),
          ),
        );

        // Increment current stock
        await customUpdate(
          'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
          variables: [Variable.withReal(qty), Variable.withInt(productId)],
          updates: {db.products},
        );

        await attachedDatabase.returnAuditLogsDao.insertAuditLog(
          returnType: returnRow.originalInvoiceId != null ? 'full' : 'manual',
          invoiceId: returnRow.originalInvoiceId,
          productId: productId,
          returnedQuantity: qty,
          returnedAmount: lineTotal,
          cashierUserId: returnedByUserId,
          cashierNameSnapshot: cashierName,
          customerId: null,
          returnReason: returnRow.reason,
          returnNote: returnRow.notes,
          stockBefore: stockBefore,
          stockAfter: stockBefore + qty,
          referenceType: 'customer_return_items',
          referenceId: itemId,
        );
      }
      return returnId;
    });
  }

  /// Full sale invoice return: restores stock, ledger rows, [CustomerReturns] record,
  /// reverses credit [debtAmount] on customer account when applicable,
  /// sets original invoice [invoiceStatus] to [InvoiceLifecycleStatus.returned]
  /// and persists return metadata ([note], [returnedByUserId]).
  ///
  /// Does not delete or rewrite original [SaleItems] or monetary totals on the sale.
  Future<int> returnFullSaleInvoice(
    int invoiceId, {
    required String note,
    required int returnedByUserId,
  }) async {
    return transaction(() async {
      final inv = await attachedDatabase.salesDao.getInvoiceById(invoiceId);
      if (inv == null) {
        throw StateError('الفاتورة غير موجودة');
      }
      if (inv.invoiceStatus == InvoiceLifecycleStatus.returned) {
        throw StateError('الفاتورة مرتجعة مسبقاً');
      }

      final dup = await (select(customerReturns)
            ..where((r) => r.originalInvoiceId.equals(invoiceId)))
          .getSingleOrNull();
      if (dup != null) {
        throw StateError('يوجد مرتجع مسجل لهذه الفاتورة');
      }

      final saleLines =
          await attachedDatabase.salesDao.getItemsForInvoice(invoiceId);
      if (saleLines.isEmpty) {
        throw StateError('لا توجد أصناف في الفاتورة');
      }

      double returnHeaderTotal = 0;
      final itemPayloads = <Map<String, dynamic>>[];

      final cashierRow = await customSelect(
        'SELECT full_name FROM users WHERE id = ?',
        variables: [Variable.withInt(returnedByUserId)],
        readsFrom: {attachedDatabase.usersTable},
      ).getSingleOrNull();
      final cashierName = cashierRow?.data['full_name'] as String?;

      String? customerName;
      final customerId = inv.customerId;
      if (customerId != null && customerId != 1) {
        final customerRow = await customSelect(
          'SELECT name FROM customers WHERE id = ?',
          variables: [Variable.withInt(customerId)],
          readsFrom: {attachedDatabase.customers},
        ).getSingleOrNull();
        customerName = customerRow?.data['name'] as String?;
      }

      for (final line in saleLines) {
        final p =
            await attachedDatabase.productsDao.getProductById(line.productId);
        final name = p?.name ?? 'منتج #${line.productId}';
        returnHeaderTotal += line.total;
        itemPayloads.add({
          'saleItemId': line.id,
          'productId': line.productId,
          'productName': name,
          'qty': line.quantity,
          'price': line.unitPrice,
          'cost': line.unitCost,
          'lineTotal': line.total,
        });
      }

      final returnNumber =
          'RET-$invoiceId-${DateTime.now().millisecondsSinceEpoch}';

      final returnId = await into(customerReturns).insert(
        CustomerReturnsCompanion(
          originalInvoiceId: Value(invoiceId),
          returnNumber: Value(returnNumber),
          total: Value(returnHeaderTotal),
          reason: const Value('إرجاع كامل للفاتورة'),
          notes: Value('فاتورة أصلية: ${inv.invoiceNumber}'),
        ),
      );

      // Persist return metadata on the original invoice row.
      final now = DateTime.now();
      await customUpdate(
        '''UPDATE sales_invoices
           SET invoice_status      = ?,
               return_date         = ?,
               return_note         = ?,
               returned_by_user_id = ?
           WHERE id = ?''',
        variables: [
          Variable.withString(InvoiceLifecycleStatus.returned),
          Variable.withInt(now.millisecondsSinceEpoch),
          Variable.withString(note.trim()),
          Variable.withInt(returnedByUserId),
          Variable.withInt(invoiceId),
        ],
        updates: {attachedDatabase.salesInvoices},
      );

      for (final item in itemPayloads) {
        final productId = item['productId'] as int;
        final saleItemId = item['saleItemId'] as int;
        final qty = (item['qty'] as num).toDouble();
        final price = (item['price'] as num).toDouble();
        final cost = (item['cost'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = (item['lineTotal'] as num).toDouble();

        final stockBefore = await attachedDatabase.stockDao.getStock(productId);

        final itemId = await into(customerReturnItems).insert(
          CustomerReturnItemsCompanion(
            returnId: Value(returnId),
            productId: Value(productId),
            productName: Value(item['productName'] as String),
            quantity: Value(qty),
            unitPrice: Value(price),
            unitCost: Value(cost),
            total: Value(lineTotal),
          ),
        );

        await into(stockLedger).insert(
          StockLedgerCompanion(
            productId: Value(productId),
            movementType: Value(StockMovementType.returnIn.code),
            referenceId: Value(itemId),
            referenceType: const Value('customer_return_items'),
            quantityChange: Value(qty),
            unitCost: Value(cost),
          ),
        );

        await customUpdate(
          'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
          variables: [Variable.withReal(qty), Variable.withInt(productId)],
          updates: {db.products},
        );

        await attachedDatabase.returnAuditLogsDao.insertAuditLog(
          returnType: 'full',
          invoiceId: invoiceId,
          saleItemId: saleItemId,
          productId: productId,
          returnedQuantity: qty,
          returnedAmount: lineTotal,
          cashierUserId: returnedByUserId,
          cashierNameSnapshot: cashierName,
          sessionId: inv.sessionId,
          customerId: customerId,
          customerNameSnapshot: customerName,
          returnReason: 'إرجاع كامل للفاتورة',
          returnNote: note.trim(),
          stockBefore: stockBefore,
          stockAfter: stockBefore + qty,
          referenceType: 'customer_return_items',
          referenceId: itemId,
        );
      }

      if (inv.debtAmount > 0 && customerId != null && customerId != 1) {
        await attachedDatabase.customerAccountsDao.recordReturn(
          customerId: customerId,
          amount: inv.debtAmount,
          returnId: returnId,
          note: 'إرجاع فاتورة ${inv.invoiceNumber}',
        );
      }

      return returnId;
    });
  }

  // --- Supplier Returns ---
  Future<List<SupplierReturn>> getAllSupplierReturns() =>
      (select(supplierReturns)
            ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
          .get();

  Future<List<SupplierReturnItem>> getSupplierReturnItems(int returnId) =>
      (select(supplierReturnItems)..where((i) => i.returnId.equals(returnId)))
          .get();

  /// Remaining quantity returnable against [purchaseItemId] (line-specific, read-only).
  ///
  /// SR.1 contract: `purchaseItem.quantity - SUM(linked supplierReturnItems.quantity)`,
  /// clamped at zero. Legacy null [purchaseItemId] rows are excluded.
  /// Returns 0.0 when the purchase item does not exist.
  ///
  /// Quantity-cap enforcement at save time belongs to SR.2+.
  Future<double> getReturnableQuantityForPurchaseItem(
      int purchaseItemId) async {
    final row = await customSelect(
      '''
      SELECT
        pi.quantity AS purchased_qty,
        COALESCE((
          SELECT SUM(sri.quantity)
          FROM supplier_return_items sri
          WHERE sri.purchase_item_id = pi.id
        ), 0) AS returned_qty
      FROM purchase_items pi
      WHERE pi.id = ?
      ''',
      variables: [Variable.withInt(purchaseItemId)],
      readsFrom: {attachedDatabase.purchaseItems, supplierReturnItems},
    ).getSingleOrNull();

    if (row == null) return 0.0;

    final purchased = (row.data['purchased_qty'] as num).toDouble();
    final returned = (row.data['returned_qty'] as num).toDouble();
    final remaining = purchased - returned;
    return remaining < 0 ? 0.0 : remaining;
  }

  /// Low-level persistence primitive for supplier returns.
  ///
  /// Contract (SR.2 hardening):
  /// - Does NOT own business orchestration or open a transaction.
  /// - Does NOT enforce returnable quantity or supplier accounting.
  /// - Expects caller-validated header/items inside a caller-owned transaction.
  /// - Performs canonical insert + RETURN_OUT + [StockGuard.deductStock].
  /// - Not a UI-facing or production entry point — use
  ///   [SupplierReturnService.postPurchaseLinkedReturn] for purchase-linked returns.
  Future<int> persistSupplierReturn({
    required SupplierReturnsCompanion header,
    required List<Map<String, dynamic>> items,
  }) async {
    final returnId = await into(supplierReturns).insert(header);
    for (final item in items) {
      final productId = item['productId'] as int;
      final qty = (item['qty'] as num).toDouble();
      final cost = (item['cost'] as num).toDouble();
      final purchaseItemId = item['purchaseItemId'] as int?;

      final itemId = await into(supplierReturnItems).insert(
        SupplierReturnItemsCompanion(
          returnId: Value(returnId),
          purchaseItemId: purchaseItemId != null
              ? Value(purchaseItemId)
              : const Value.absent(),
          productId: Value(productId),
          productName: Value(item['productName'] as String),
          quantity: Value(qty),
          unitCost: Value(cost),
          total: Value(qty * cost),
        ),
      );

      await into(stockLedger).insert(
        StockLedgerCompanion(
          productId: Value(productId),
          movementType: Value(StockMovementType.returnOut.code),
          referenceId: Value(itemId),
          referenceType: const Value('supplier_return_items'),
          quantityChange: Value(-qty),
          unitCost: Value(cost),
        ),
      );

      await StockGuard.deductStock(
        db: attachedDatabase,
        productId: productId,
        quantity: qty,
      );
    }
    return returnId;
  }

  /// Legacy/manual supplier return persistence (stock only, no supplier accounting).
  ///
  /// **Not for purchase-linked returns.** If [header.purchaseInvoiceId] is set or
  /// any item carries [purchaseItemId], this method rejects and directs callers to
  /// [SupplierReturnService.postPurchaseLinkedReturn].
  ///
  /// Item payload keys: productId, productName, qty, cost (no purchaseItemId).
  @Deprecated(
    'Purchase-linked supplier returns must be posted through '
    'SupplierReturnService.postPurchaseLinkedReturn(). '
    'Use saveSupplierReturn only for legacy/manual unlinked returns.',
  )
  Future<int> saveSupplierReturn({
    required SupplierReturnsCompanion header,
    required List<Map<String, dynamic>> items,
  }) async {
    final headerPurchaseId = header.purchaseInvoiceId.present
        ? header.purchaseInvoiceId.value
        : null;
    final hasLinkedItems = items.any((item) => item['purchaseItemId'] != null);

    if (headerPurchaseId != null || hasLinkedItems) {
      throw const SupplierReturnDirectPostingForbiddenException();
    }

    return transaction(
      () => persistSupplierReturn(header: header, items: items),
    );
  }
}
