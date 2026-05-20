// lib/core/services/partial_return_service.dart
//
// Orchestrates partial item returns from sale invoices.
//
// Design rules:
//  - Original sale_items rows are NEVER modified.
//  - Every partial return runs inside a single DB transaction.
//  - Stock restoration is atomic with the return record insertion.
//  - Stock movements table is updated for audit trail.
//  - Invoice status is auto-updated after each return batch.
//  - ALL Drift Companion / generated-type usage lives in DAOs.

import 'package:drift/drift.dart' show Variable;
import '../database/app_database.dart';
import '../constants/invoice_lifecycle.dart';
import '../constants/movement_types.dart';

// Describes one product line being partially returned.
class PartialReturnLine {
  final int saleItemId;
  final int productId;
  final double quantity;
  final double unitPrice;
  final double unitCost;

  const PartialReturnLine({
    required this.saleItemId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.unitCost = 0.0,
  });
}

class PartialReturnService {
  final AppDatabase _db;

  PartialReturnService(this._db);

  // ---- Read helpers -------------------------------------------------------

  // Total quantity already returned for a specific sale line.
  Future<double> getReturnedQuantityForSaleItem(int saleItemId) =>
      _db.saleItemReturnsDao.getReturnedQuantityForSaleItem(saleItemId);

  // Quantity still eligible for return: sold_qty - already_returned_qty.
  Future<double> getAvailableReturnQuantity(int saleItemId) async {
    final soldQty =
        await _db.saleItemReturnsDao.getSaleItemQuantity(saleItemId);
    if (soldQty == null) return 0.0;
    final alreadyReturned = await getReturnedQuantityForSaleItem(saleItemId);
    final available = soldQty - alreadyReturned;
    return available < 0 ? 0.0 : available;
  }

  // Per-line return summary for building return history views.
  Future<Map<int, double>> getReturnedQuantitiesForInvoice(
          int saleInvoiceId) =>
      _db.saleItemReturnsDao.getReturnedQuantitiesForInvoice(saleInvoiceId);

  // ---- Validation ---------------------------------------------------------

  // Throws if the requested quantity is invalid.
  void validateReturnQuantity({
    required double quantity,
    required double available,
    required int saleItemId,
  }) {
    if (quantity <= 0) {
      throw ArgumentError(
          'كمية الإرجاع يجب أن تكون أكبر من الصفر (صنف #$saleItemId)');
    }
    if (quantity > available + 0.0001) {
      throw StateError(
          'كمية الإرجاع ($quantity) تتجاوز الكمية المتاحة ($available) للصنف #$saleItemId');
    }
  }

  // ---- Main operation -----------------------------------------------------

  // Processes a batch of partial return lines atomically.
  // All lines MUST belong to the same saleInvoiceId.
  //
  // Steps inside the transaction:
  //   1. Validate each line.
  //   2. Insert sale_item_returns record  (via DAO).
  //   3. Restore stock in products table  (via DAO).
  //   4. Insert stock_ledger entry        (via DAO - low-level audit).
  //   5. Insert stock_movements entry     (via stockMovementsDao - business audit).
  //   6. Auto-update invoice_status       (via DAO).
  Future<void> processPartialReturn({
    required int saleInvoiceId,
    required List<PartialReturnLine> lines,
    required int returnedByUserId,
    String? note,
  }) async {
    if (lines.isEmpty) return;

    final inv = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (inv == null) throw StateError('الفاتورة غير موجودة');
    if (inv.invoiceStatus == InvoiceLifecycleStatus.returned) {
      throw StateError(
          'الفاتورة مرتجعة بالكامل مسبقاً - لا يمكن الإرجاع الجزئي');
    }

    await _db.transaction(() async {
      // -- Audit snapshots (looked up once per transaction) -----------------
      final cashierRow = await _db.customSelect(
        'SELECT full_name FROM users WHERE id = ?',
        variables: [Variable.withInt(returnedByUserId)],
        readsFrom: {_db.usersTable},
      ).getSingleOrNull();
      final cashierName = cashierRow?.data['full_name'] as String?;

      String? customerName;
      final customerId = inv.customerId;
      if (customerId != null && customerId != 1) {
        final customerRow = await _db.customSelect(
          'SELECT name FROM customers WHERE id = ?',
          variables: [Variable.withInt(customerId)],
          readsFrom: {_db.customers},
        ).getSingleOrNull();
        customerName = customerRow?.data['name'] as String?;
      }
      // ---------------------------------------------------------------------

      for (final line in lines) {
        // 1. Validate
        final available = await getAvailableReturnQuantity(line.saleItemId);
        validateReturnQuantity(
          quantity: line.quantity,
          available: available,
          saleItemId: line.saleItemId,
        );

        // 2. Insert return line record
        final returnLineId = await _db.saleItemReturnsDao.insertReturnLine(
          saleInvoiceId: saleInvoiceId,
          saleItemId: line.saleItemId,
          productId: line.productId,
          returnedQuantity: line.quantity,
          unitPriceAtReturn: line.unitPrice,
          returnTotal: line.quantity * line.unitPrice,
          returnedByUserId: returnedByUserId,
          returnReasonNote: note,
        );

        // 3. Restore stock
        final stockBefore = await _db.stockDao.getStock(line.productId);
        await _db.saleItemReturnsDao.restoreProductStock(
            line.productId, line.quantity);

        // 4. Stock ledger (low-level accounting trail)
        await _db.saleItemReturnsDao.insertStockLedgerReturn(
          productId: line.productId,
          referenceId: returnLineId,
          quantity: line.quantity,
          unitCost: line.unitCost,
        );

        // 5. Stock movement (business-level audit)
        await _db.stockMovementsDao.recordMovement(
          productId: line.productId,
          movementType: StockMovementKind.partialReturn,
          quantityChange: line.quantity,
          stockBefore: stockBefore,
          stockAfter: stockBefore + line.quantity,
          referenceId: saleInvoiceId,
          referenceType: 'sale_invoice',
          note: note,
          createdByUserId: returnedByUserId,
        );

        // 6. Immutable audit row (same transaction — atomic with return)
        await _db.returnAuditLogsDao.insertAuditLog(
          returnType: 'partial',
          invoiceId: saleInvoiceId,
          saleItemId: line.saleItemId,
          productId: line.productId,
          returnedQuantity: line.quantity,
          returnedAmount: line.quantity * line.unitPrice,
          cashierUserId: returnedByUserId,
          cashierNameSnapshot: cashierName,
          sessionId: inv.sessionId,
          customerId: customerId,
          customerNameSnapshot: customerName,
          returnReason: 'إرجاع جزئي',
          returnNote: note,
          stockBefore: stockBefore,
          stockAfter: stockBefore + line.quantity,
          referenceType: 'sale_item_return',
          referenceId: returnLineId,
        );
      }

      // 7. Recalculate and persist invoice status
      await _refreshInvoiceStatus(saleInvoiceId);
    });
  }

  // ---- Invoice status auto-update -----------------------------------------

  // Recalculates invoice_status based on returned quantities and persists.
  Future<void> _refreshInvoiceStatus(int saleInvoiceId) async {
    final saleLines = await _db.salesDao.getItemsForInvoice(saleInvoiceId);
    if (saleLines.isEmpty) return;

    bool anyReturned = false;
    bool allFullyReturned = true;

    for (final line in saleLines) {
      final returned =
          await _db.saleItemReturnsDao.getReturnedQuantityForSaleItem(line.id);
      if (returned > 0) anyReturned = true;
      if (returned < line.quantity - 0.0001) allFullyReturned = false;
    }

    if (!anyReturned) return;

    final newStatus = allFullyReturned
        ? InvoiceLifecycleStatus.returned
        : InvoiceLifecycleStatus.partiallyReturned;

    await _db.saleItemReturnsDao.setInvoiceStatus(saleInvoiceId, newStatus);
  }

  // Public wrapper to recalculate status without performing a return.
  Future<void> refreshInvoiceStatus(int saleInvoiceId) =>
      _db.transaction(() => _refreshInvoiceStatus(saleInvoiceId));
}