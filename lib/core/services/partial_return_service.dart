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
//  - Credit receivable reversal for credit invoices (Phase C.1).
//  - ALL Drift Companion / generated-type usage lives in DAOs.

import 'package:drift/drift.dart' show Variable;

import '../database/app_database.dart';
import '../constants/invoice_lifecycle.dart';
import '../constants/movement_types.dart';
import '../activity/activity_categories.dart';
import '../activity/activity_types.dart';
import 'activity_logger_service.dart';
import 'customer_return_credit.dart';

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

typedef CustomerReturnCreditPoster = Future<void> Function({
  required int customerId,
  required double amount,
  required int returnId,
  String note,
});

class PartialReturnService {
  final AppDatabase _db;
  final CustomerReturnCreditPoster? _creditPoster;

  PartialReturnService(this._db, {CustomerReturnCreditPoster? creditPoster})
      : _creditPoster = creditPoster;

  /// Test seam for accounting rollback tests.
  factory PartialReturnService.withCreditPoster(
    AppDatabase db, {
    required CustomerReturnCreditPoster creditPoster,
  }) =>
      PartialReturnService(db, creditPoster: creditPoster);

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
  Future<Map<int, double>> getReturnedQuantitiesForInvoice(int saleInvoiceId) =>
      _db.saleItemReturnsDao.getReturnedQuantitiesForInvoice(saleInvoiceId);

  /// Whether any sale line on [saleInvoiceId] still has returnable quantity.
  Future<bool> hasRemainingReturnableQuantity(int saleInvoiceId) async {
    final saleLines = await _db.salesDao.getItemsForInvoice(saleInvoiceId);
    for (final line in saleLines) {
      final available = await getAvailableReturnQuantity(line.id);
      if (available > 0.0001) return true;
    }
    return false;
  }

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

  /// Returns all remaining quantities on [saleInvoiceId] (Return All Remaining).
  Future<void> returnAllRemainingSaleInvoice({
    required int saleInvoiceId,
    required int returnedByUserId,
    required String note,
  }) async {
    final inv = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (inv == null) throw StateError('الفاتورة غير موجودة');
    if (inv.invoiceStatus == InvoiceLifecycleStatus.returned) {
      throw StateError('الفاتورة مرتجعة بالكامل مسبقاً');
    }

    final saleLines = await _db.salesDao.getItemsForInvoice(saleInvoiceId);
    if (saleLines.isEmpty) {
      throw StateError('لا توجد أصناف في الفاتورة');
    }

    final lines = <PartialReturnLine>[];
    for (final line in saleLines) {
      final available = await getAvailableReturnQuantity(line.id);
      if (available > 0.0001) {
        lines.add(
          PartialReturnLine(
            saleItemId: line.id,
            productId: line.productId,
            quantity: available,
            unitPrice: line.unitPrice,
            unitCost: line.unitCost,
          ),
        );
      }
    }

    if (lines.isEmpty) {
      throw StateError('لا توجد كميات متبقية للإرجاع');
    }

    await processPartialReturn(
      saleInvoiceId: saleInvoiceId,
      lines: lines,
      returnedByUserId: returnedByUserId,
      note: note,
      returnReason: 'إرجاع الكل',
      persistReturnMetadata: true,
    );
  }

  // Processes a batch of partial return lines atomically.
  // All lines MUST belong to the same saleInvoiceId.
  Future<void> processPartialReturn({
    required int saleInvoiceId,
    required List<PartialReturnLine> lines,
    required int returnedByUserId,
    String? note,
    String returnReason = 'إرجاع جزئي',
    bool persistReturnMetadata = false,
  }) async {
    if (lines.isEmpty) return;

    final inv = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (inv == null) throw StateError('الفاتورة غير موجودة');
    if (inv.invoiceStatus == InvoiceLifecycleStatus.returned) {
      throw StateError(
          'الفاتورة مرتجعة بالكامل مسبقاً - لا يمكن الإرجاع الجزئي');
    }

    await _db.transaction(() async {
      final saleLines = await _db.salesDao.getItemsForInvoice(saleInvoiceId);

      // -- Audit snapshots (looked up once per transaction) -----------------
      final cashierRow = await _db.customSelect(
        'SELECT full_name FROM users WHERE id = ?',
        variables: [Variable.withInt(returnedByUserId)],
        readsFrom: {_db.usersTable},
      ).getSingleOrNull();
      final cashierName = cashierRow?.data['full_name'] as String?;

      final customerId = inv.customerId;
      String? customerName;
      if (customerId != null && customerId != 1) {
        final customerRow = await _db.customSelect(
          'SELECT name FROM customers WHERE id = ?',
          variables: [Variable.withInt(customerId)],
          readsFrom: {_db.customers},
        ).getSingleOrNull();
        customerName = customerRow?.data['name'] as String?;
      }
      // ---------------------------------------------------------------------

      int? firstReturnLineId;
      final returnedQtyBySaleItemId = <int, double>{};

      for (final line in lines) {
        // 1. Validate against current DB state inside txn
        final soldQty =
            await _db.saleItemReturnsDao.getSaleItemQuantity(line.saleItemId);
        if (soldQty == null) {
          throw StateError('الصنف #${line.saleItemId} غير موجود في الفاتورة');
        }
        final alreadyReturned = await _db.saleItemReturnsDao
            .getReturnedQuantityForSaleItem(line.saleItemId);
        final available = soldQty - alreadyReturned;
        validateReturnQuantity(
          quantity: line.quantity,
          available: available < 0 ? 0 : available,
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
        firstReturnLineId ??= returnLineId;
        returnedQtyBySaleItemId[line.saleItemId] = line.quantity;

        // 3. Restore stock
        final stockBefore = await _db.stockDao.getStock(line.productId);
        await _db.saleItemReturnsDao
            .restoreProductStock(line.productId, line.quantity);

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
          returnReason: returnReason,
          returnNote: note,
          stockBefore: stockBefore,
          stockAfter: stockBefore + line.quantity,
          referenceType: 'sale_item_return',
          referenceId: returnLineId,
        );
      }

      // 7. Customer credit reversal (credit invoices only)
      if (inv.debtAmount > 0 &&
          customerId != null &&
          customerId != 1 &&
          firstReturnLineId != null) {
        final proposed = CustomerReturnCredit.creditReversalForSaleLines(
          invoice: inv,
          saleLines: saleLines,
          returnedQtyBySaleItemId: returnedQtyBySaleItemId,
        );
        final alreadyReversed =
            await _db.customerAccountsDao.getCreditReversalTotalForSaleInvoice(
          customerId: customerId,
          invoiceId: saleInvoiceId,
        );
        final creditAmount = CustomerReturnCredit.cappedCreditReversal(
          proposed: proposed,
          invoiceDebtAmount: inv.debtAmount,
          alreadyReversed: alreadyReversed,
        );
        if (creditAmount > 0.0001) {
          if (_creditPoster != null) {
            await _creditPoster!(
              customerId: customerId,
              amount: creditAmount,
              returnId: firstReturnLineId,
              note: 'إرجاع فاتورة ${inv.invoiceNumber}',
            );
          } else {
            await _db.customerAccountsDao.recordReturnInTransaction(
              customerId: customerId,
              amount: creditAmount,
              returnId: firstReturnLineId,
              note: 'إرجاع فاتورة ${inv.invoiceNumber}',
            );
          }
        }
      }

      // 8. Recalculate and persist invoice status
      final allFullyReturned = await _refreshInvoiceStatus(saleInvoiceId);

      if (persistReturnMetadata && allFullyReturned && note != null) {
        await _db.saleItemReturnsDao.setInvoiceReturnMetadata(
          saleInvoiceId: saleInvoiceId,
          note: note,
          returnedByUserId: returnedByUserId,
        );
      }
    });

    await ActivityLoggerService(_db).logWarning(
      activityType: ActivityTypes.returnPartial,
      category: ActivityCategories.returns,
      action: 'partial_return',
      title: 'إرجاع جزئي لفاتورة',
      entityType: 'invoice',
      entityId: saleInvoiceId,
      metadata: {'lines': lines.length, 'note': note},
    );
  }

  // ---- Invoice status auto-update -----------------------------------------

  /// Returns true when every line is fully returned after refresh.
  Future<bool> _refreshInvoiceStatus(int saleInvoiceId) async {
    final saleLines = await _db.salesDao.getItemsForInvoice(saleInvoiceId);
    if (saleLines.isEmpty) return false;

    bool anyReturned = false;
    bool allFullyReturned = true;

    for (final line in saleLines) {
      final returned =
          await _db.saleItemReturnsDao.getReturnedQuantityForSaleItem(line.id);
      if (returned > 0) anyReturned = true;
      if (returned < line.quantity - 0.0001) allFullyReturned = false;
    }

    if (!anyReturned) return false;

    final newStatus = allFullyReturned
        ? InvoiceLifecycleStatus.returned
        : InvoiceLifecycleStatus.partiallyReturned;

    await _db.saleItemReturnsDao.setInvoiceStatus(saleInvoiceId, newStatus);
    return allFullyReturned;
  }

  // Public wrapper to recalculate status without performing a return.
  Future<void> refreshInvoiceStatus(int saleInvoiceId) =>
      _db.transaction(() => _refreshInvoiceStatus(saleInvoiceId));
}
