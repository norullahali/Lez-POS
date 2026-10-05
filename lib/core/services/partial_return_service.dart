// lib/core/services/partial_return_service.dart
//
// Orchestrates partial item returns from sale invoices.
//
// Design rules:
//  - Original sale_items rows are NEVER modified.
//  - Business mutations run inside caller-owned transactions via
//    [executePartialReturnInTransaction].
//  - Stock restoration is atomic with the return record insertion.
//  - Stock movements table is updated for audit trail.
//  - Invoice status is auto-updated after each return batch.
//  - Credit receivable reversal for credit invoices (Phase C.1).
//  - Invoice-linked customer_returns document (Phase C.2.6).

import 'package:drift/drift.dart' show Variable;

import '../database/app_database.dart';
import '../database/daos/returns_dao.dart';
import '../constants/invoice_lifecycle.dart';
import '../constants/movement_types.dart';
import '../activity/activity_categories.dart';
import '../activity/activity_types.dart';
import 'activity_logger_service.dart';
import 'customer_return_credit.dart';
import 'customer_invoice_return_fingerprint.dart';
import 'customer_invoice_return_posting_result.dart';

/// Minimal caller-controlled line for partial invoice returns (B16).
class CustomerInvoicePartialReturnLine {
  final int saleItemId;
  final double quantity;

  const CustomerInvoicePartialReturnLine({
    required this.saleItemId,
    required this.quantity,
  });
}

// Describes one product line being partially returned (legacy UI/tests).
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

  factory PartialReturnService.withCreditPoster(
    AppDatabase db, {
    required CustomerReturnCreditPoster creditPoster,
  }) =>
      PartialReturnService(db, creditPoster: creditPoster);

  Future<double> getReturnedQuantityForSaleItem(int saleItemId) =>
      _db.saleItemReturnsDao.getReturnedQuantityForSaleItem(saleItemId);

  Future<double> getAvailableReturnQuantity(int saleItemId) async {
    final soldQty =
        await _db.saleItemReturnsDao.getSaleItemQuantity(saleItemId);
    if (soldQty == null) return 0.0;
    final alreadyReturned = await getReturnedQuantityForSaleItem(saleItemId);
    final available = soldQty - alreadyReturned;
    return available < 0 ? 0.0 : available;
  }

  Future<Map<int, double>> getReturnedQuantitiesForInvoice(int saleInvoiceId) =>
      _db.saleItemReturnsDao.getReturnedQuantitiesForInvoice(saleInvoiceId);

  Future<bool> hasRemainingReturnableQuantity(int saleInvoiceId) async {
    final saleLines = await _db.salesDao.getItemsForInvoice(saleInvoiceId);
    for (final line in saleLines) {
      final available = await getAvailableReturnQuantity(line.id);
      if (available > 0.0001) return true;
    }
    return false;
  }

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

  /// Returns all remaining quantities on [saleInvoiceId] inside caller txn.
  Future<CustomerInvoicePartialReturnExecution>
      executeReturnAllRemainingInTransaction({
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

    final lines = <CustomerInvoicePartialReturnLine>[];
    for (final line in saleLines) {
      final soldQty =
          await _db.saleItemReturnsDao.getSaleItemQuantity(line.id);
      if (soldQty == null) continue;
      final alreadyReturned = await _db.saleItemReturnsDao
          .getReturnedQuantityForSaleItem(line.id);
      final available = soldQty - alreadyReturned;
      if (available > 0.0001) {
        lines.add(
          CustomerInvoicePartialReturnLine(
            saleItemId: line.id,
            quantity: available,
          ),
        );
      }
    }

    if (lines.isEmpty) {
      throw StateError('لا توجد كميات متبقية للإرجاع');
    }

    return executePartialReturnInTransaction(
      saleInvoiceId: saleInvoiceId,
      lines: lines,
      returnedByUserId: returnedByUserId,
      note: note,
      returnReason: 'إرجاع الكل',
      persistReturnMetadata: true,
    );
  }

  Future<void> returnAllRemainingSaleInvoice({
    required int saleInvoiceId,
    required int returnedByUserId,
    required String note,
  }) async {
    await _db.transaction(() async {
      await executeReturnAllRemainingInTransaction(
        saleInvoiceId: saleInvoiceId,
        returnedByUserId: returnedByUserId,
        note: note,
      );
    });
  }

  /// Core partial-return mutation. Must run inside caller's transaction.
  Future<CustomerInvoicePartialReturnExecution>
      executePartialReturnInTransaction({
    required int saleInvoiceId,
    required List<CustomerInvoicePartialReturnLine> lines,
    required int returnedByUserId,
    String? note,
    String returnReason = 'إرجاع جزئي',
    bool persistReturnMetadata = false,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('empty partial return lines');
    }

    final inv = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (inv == null) throw StateError('الفاتورة غير موجودة');
    if (inv.invoiceStatus == InvoiceLifecycleStatus.returned) {
      throw StateError(
          'الفاتورة مرتجعة بالكامل مسبقاً - لا يمكن الإرجاع الجزئي');
    }

    final invNow = await _db.salesDao.getInvoiceById(saleInvoiceId);
    if (invNow == null) throw StateError('الفاتورة غير موجودة');
    if (invNow.invoiceStatus == InvoiceLifecycleStatus.returned) {
      throw StateError(
          'الفاتورة مرتجعة بالكامل مسبقاً - لا يمكن الإرجاع الجزئي');
    }

    final saleLines = await _db.salesDao.getItemsForInvoice(saleInvoiceId);
    final saleLineById = {for (final line in saleLines) line.id: line};

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

    int? firstReturnLineId;
    final returnedQtyBySaleItemId = <int, double>{};
    final documentLines = <CustomerReturnDocumentLine>[];
    var batchGoodsTotal = 0.0;

    final aggregated = aggregatePartialReturnLines(
      lines
          .map(
            (line) => CustomerInvoicePartialReturnLineInput(
              saleItemId: line.saleItemId,
              quantity: line.quantity,
            ),
          )
          .toList(),
    );

    for (final entry in aggregated.entries) {
      final saleItemId = entry.key;
      final requestedQty = entry.value;
      final saleItem = saleLineById[saleItemId];
      if (saleItem == null) {
        throw StateError('الصنف #$saleItemId غير موجود في الفاتورة');
      }

      final soldQty =
          await _db.saleItemReturnsDao.getSaleItemQuantity(saleItemId);
      if (soldQty == null) {
        throw StateError('الصنف #$saleItemId غير موجود في الفاتورة');
      }
      final alreadyReturned =
          await _db.saleItemReturnsDao.getReturnedQuantityForSaleItem(
        saleItemId,
      );
      final available = soldQty - alreadyReturned;
      validateReturnQuantity(
        quantity: requestedQty,
        available: available < 0 ? 0 : available,
        saleItemId: saleItemId,
      );

      final unitPrice = saleItem.unitPrice;
      final unitCost = saleItem.unitCost;
      final productId = saleItem.productId;

      final returnLineId = await _db.saleItemReturnsDao
          .insertSaleItemReturnIfWithinSaleLineCap(
        saleInvoiceId: saleInvoiceId,
        saleItemId: saleItemId,
        productId: productId,
        returnedQuantity: requestedQty,
        unitPriceAtReturn: unitPrice,
        returnTotal: requestedQty * unitPrice,
        returnedByUserId: returnedByUserId,
        returnReasonNote: note,
      );
      if (returnLineId == null) {
        final alreadyReturnedNow = await _db.saleItemReturnsDao
            .getReturnedQuantityForSaleItem(saleItemId);
        final availableNow = soldQty - alreadyReturnedNow;
        throw StateError(
          'كمية الإرجاع ($requestedQty) تتجاوز الكمية المتاحة (${availableNow < 0 ? 0 : availableNow}) للصنف #$saleItemId',
        );
      }
      firstReturnLineId ??= returnLineId;
      returnedQtyBySaleItemId[saleItemId] = requestedQty;

      final lineTotal = requestedQty * unitPrice;
      batchGoodsTotal += lineTotal;
      final product = await _db.productsDao.getProductById(productId);
      final productName = product?.name ?? 'منتج #$productId';
      documentLines.add(
        CustomerReturnDocumentLine(
          productId: productId,
          productName: productName,
          quantity: requestedQty,
          unitPrice: unitPrice,
          unitCost: unitCost,
          lineTotal: lineTotal,
        ),
      );

      final stockBefore = await _db.stockDao.getStock(productId);
      await _db.saleItemReturnsDao.restoreProductStock(productId, requestedQty);

      await _db.saleItemReturnsDao.insertStockLedgerReturn(
        productId: productId,
        referenceId: returnLineId,
        quantity: requestedQty,
        unitCost: unitCost,
      );

      await _db.stockMovementsDao.recordMovement(
        productId: productId,
        movementType: StockMovementKind.partialReturn,
        quantityChange: requestedQty,
        stockBefore: stockBefore,
        stockAfter: stockBefore + requestedQty,
        referenceId: saleInvoiceId,
        referenceType: 'sale_invoice',
        note: note,
        createdByUserId: returnedByUserId,
      );

      await _db.returnAuditLogsDao.insertAuditLog(
        returnType: 'partial',
        invoiceId: saleInvoiceId,
        saleItemId: saleItemId,
        productId: productId,
        returnedQuantity: requestedQty,
        returnedAmount: lineTotal,
        cashierUserId: returnedByUserId,
        cashierNameSnapshot: cashierName,
        sessionId: inv.sessionId,
        customerId: customerId,
        customerNameSnapshot: customerName,
        returnReason: returnReason,
        returnNote: note,
        stockBefore: stockBefore,
        stockAfter: stockBefore + requestedQty,
        referenceType: 'sale_item_return',
        referenceId: returnLineId,
      );
    }

    final customerReturnId = await _db.returnsDao.upsertPartialReturnDocumentHeader(
      saleInvoiceId: saleInvoiceId,
      invoiceNumber: inv.invoiceNumber,
      batchGoodsTotal: batchGoodsTotal,
      returnReason: returnReason,
    );
    await _db.returnsDao.appendCustomerReturnDocumentLines(
      returnId: customerReturnId,
      lines: documentLines,
    );

    if (inv.debtAmount > 0 &&
        customerId != null &&
        customerId != 1 &&
        firstReturnLineId != null) {
      final proposed = CustomerReturnCredit.creditReversalForSaleLines(
        invoice: inv,
        saleLines: saleLines,
        returnedQtyBySaleItemId: returnedQtyBySaleItemId,
      );
      if (proposed > 0.0001) {
        if (_creditPoster != null) {
          await _creditPoster!(
            customerId: customerId,
            amount: proposed,
            returnId: firstReturnLineId,
            note: 'إرجاع فاتورة ${inv.invoiceNumber}',
          );
        } else {
          await _db.customerAccountsDao
              .recordReturnInTransactionIfWithinInvoiceCreditCap(
            customerId: customerId,
            invoiceId: saleInvoiceId,
            proposedAmount: proposed,
            referenceId: firstReturnLineId,
            note: 'إرجاع فاتورة ${inv.invoiceNumber}',
          );
        }
      }
    }

    final allFullyReturned = await _refreshInvoiceStatus(saleInvoiceId);

    if (persistReturnMetadata && allFullyReturned && note != null) {
      await _db.saleItemReturnsDao.setInvoiceReturnMetadata(
        saleInvoiceId: saleInvoiceId,
        note: note,
        returnedByUserId: returnedByUserId,
      );
    }

    return CustomerInvoicePartialReturnExecution(
      customerReturnId: customerReturnId,
      primaryReferenceId: firstReturnLineId!,
    );
  }

  Future<void> processPartialReturn({
    required int saleInvoiceId,
    required List<PartialReturnLine> lines,
    required int returnedByUserId,
    String? note,
    String returnReason = 'إرجاع جزئي',
    bool persistReturnMetadata = false,
  }) async {
    if (lines.isEmpty) return;

    await _db.transaction(() async {
      await executePartialReturnInTransaction(
        saleInvoiceId: saleInvoiceId,
        lines: lines
            .map(
              (line) => CustomerInvoicePartialReturnLine(
                saleItemId: line.saleItemId,
                quantity: line.quantity,
              ),
            )
            .toList(),
        returnedByUserId: returnedByUserId,
        note: note,
        returnReason: returnReason,
        persistReturnMetadata: persistReturnMetadata,
      );
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

  Future<void> refreshInvoiceStatus(int saleInvoiceId) =>
      _db.transaction(() => _refreshInvoiceStatus(saleInvoiceId));
}
