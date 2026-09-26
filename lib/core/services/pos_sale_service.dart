import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../constants/movement_types.dart';
import '../services/settings_service.dart';
import '../services/stock_guard.dart';
import '../../features/loyalty/services/loyalty_service.dart';
import '../activity/activity_categories.dart';
import '../activity/activity_types.dart';
import 'activity_logger_service.dart';

/// Service to handle POS sales and returns orchestration.
class PosSaleService {
  final AppDatabase db;
  late final LoyaltyService _loyaltyService =
      LoyaltyService(db, SettingsService(db));

  PosSaleService(this.db);

  /// Processes a complete sale transaction.
  /// This method is the single source of truth for POS sales.
  ///
  /// Loyalty parameters (optional):
  ///   [pointsUsed]   – points the customer chose to redeem (deducted).
  ///   [netSaleTotal] – the net amount actually paid (used to compute earned pts).
  Future<int> processSale({
    required SalesInvoicesCompanion invoice,
    required List<SaleItemsCompanion> items,
    double? debtAmount,
    double pointsUsed = 0,
    double netSaleTotal = 0,
    int? approvedByUserId,
  }) async {
    try {
      return await db.transaction(() async {
        // 0. Validate Returns and Refund Limits
        final hasReturns = items.any((i) => i.quantity.present && i.quantity.value < 0);
        double totalReturnAmount = 0;
        if (hasReturns) {
          totalReturnAmount = items
              .where((i) => i.quantity.present && i.quantity.value < 0)
              .fold(0.0, (s, i) => s + i.total.value.abs());

          final cashierId = invoice.createdByUserId.present ? invoice.createdByUserId.value : null;
          if (cashierId != null) {
            final cashier = await db.usersDao.getUserById(cashierId);
            if (cashier != null && cashier.roleId != 1) { // Skip checks for Admin
              final perms = await db.usersDao.getRolePermissionsKeys(cashier.roleId);
              if (!perms.contains('pos.refund')) {
                throw Exception('ليس لديك صلاحية لإجراء المرتجعات.');
              }
              if (totalReturnAmount > cashier.refundLimit) {
                if (approvedByUserId == null) {
                  throw Exception('تجاوزت الحد المسموح للمرتجع. يتطلب الأمر موافقة مشرف.');
                }
              }
            }
          }
        }

        // 1. Insert SalesInvoice record
        final invoiceId = await db.into(db.salesInvoices).insert(invoice);

        await ActivityLoggerService(db).logInfo(
          activityType: ActivityTypes.invoiceCreated,
          category: ActivityCategories.sales,
          action: 'create',
          title: 'إنشاء فاتورة',
          entityType: 'invoice',
          entityId: invoiceId,
          metadata: {
            'invoiceNumber': invoice.invoiceNumber.value,
            'total': invoice.total.value,
          },
        );

        // 2. Process items using batch for performance
        await db.batch((batch) {
          for (final item in items) {
            // Add sale item to batch
            final itemWithInvoice = item.copyWith(invoiceId: Value(invoiceId));
            batch.insert(db.saleItems, itemWithInvoice);

            // Add stock ledger entry to batch (audit trail)
            batch.insert(
              db.stockLedger,
              StockLedgerCompanion(
                productId: item.productId,
                movementType: Value(StockMovementType.sale.code),
                referenceType: const Value('sale_items'),
                quantityChange: Value(-item.quantity.value),
                unitCost: item.unitCost,
              ),
            );
          }
        });

        // Update stock for each item inside the transaction.
        // Positive qty  = regular sale   → guarded deduction (never goes negative).
        // Negative qty  = return-in-sale → safe increment back into stock.
        for (final item in items) {
          final qty = item.quantity.value;
          if (qty > 0) {
            await StockGuard.deductStock(
              db: db,
              productId: item.productId.value,
              quantity: qty,
            );
          } else if (qty < 0) {
            await db.customUpdate(
              'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
              variables: [
                Variable.withReal(qty.abs()),
                Variable.withInt(item.productId.value),
              ],
              updates: {db.products},
            );
          }
        }

        // 3. Update CustomerAccount balance/debt if provided
        if (debtAmount != null && debtAmount > 0) {
          final customerId = invoice.customerId.value;
          if (customerId != null && customerId != 1) { // 1 = General Customer
            await db.customerAccountsDao.recordSale(
              customerId: customerId,
              amount: debtAmount,
              invoiceId: invoiceId,
              note: 'فاتورة رقم ${invoice.invoiceNumber.value}',
            );
          }
        }

        // 4. Loyalty points — earn & deduct (no-op for walk-in customer)
        final customerId = invoice.customerId.value;
        if (customerId != null && customerId != 1) {
          final earned = await _loyaltyService.earnPoints(netSaleTotal);
          await _loyaltyService.applyPostSalePoints(
            customerId: customerId,
            earnedPoints: earned,
            usedPoints: pointsUsed,
          );
        }

        // 5. Logging
        final approvalText = approvedByUserId != null ? ' | Approved By: $approvedByUserId' : '';
        await db.into(db.logsTable).insert(
          LogsTableCompanion.insert(
            userId: Value(invoice.processedByUserId.value ?? invoice.createdByUserId.value),
            approvedByUserId: Value(approvedByUserId),
            actionType: hasReturns ? 'SALE_WITH_RETURN' : 'SALE_CONFIRMED',
            amount: Value(hasReturns ? totalReturnAmount : invoice.total.value),
            details: Value('Invoice ID: $invoiceId (Ref: $invoiceId)$approvalText'),
          )
        );

        return invoiceId;
      });
    } catch (e, st) {
      debugPrint('[PosSaleService] Error in processSale: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في إتمام عملية البيع: ${e.toString()}');
    }
  }

  /// Processes a quick return without an original invoice.
  Future<void> processQuickReturn({
    required int productId,
    required double quantity,
    required double refundAmount,
    required int userId,
    required String reason,
    int? approvedByUserId,
  }) async {
    try {
      await db.transaction(() async {
        // 1. Insert CustomerReturns record (originalInvoiceId is null)
        final returnNumber = 'RET-QUICK-${DateTime.now().millisecondsSinceEpoch}';

        final returnId = await db.into(db.customerReturns).insert(
              CustomerReturnsCompanion.insert(
                originalInvoiceId: const Value(null),
                returnNumber: returnNumber,
                total: Value(refundAmount),
                reason: Value(reason),
                returnDate: Value(DateTime.now()),
              ),
            );

        // Fetch product info to get cost and name
        final product = await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingle();
        final stockBefore = await db.stockDao.getStock(productId);

        // 2. Insert CustomerReturnItems record
        final itemId = await db.into(db.customerReturnItems).insert(
              CustomerReturnItemsCompanion.insert(
                returnId: returnId,
                productId: productId,
                productName: product.name,
                quantity: quantity,
                unitPrice: quantity > 0 ? refundAmount / quantity : 0,
                unitCost: Value(product.costPrice),
                total: refundAmount,
              ),
            );

        // 3. Update stock ledger (audit trail)
        await db.into(db.stockLedger).insert(
              StockLedgerCompanion.insert(
                productId: productId,
                movementType: StockMovementType.returnIn.code,
                referenceId: Value(itemId),
                referenceType: const Value('customer_return_items'),
                quantityChange: quantity, // Positive
                unitCost: Value(product.costPrice),
              ),
            );

        // Increment current stock
        await db.customUpdate(
          'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
          variables: [Variable.withReal(quantity), Variable.withInt(productId)],
          updates: {db.products},
        );

        final cashierRow = await db.customSelect(
          'SELECT full_name FROM users WHERE id = ?',
          variables: [Variable.withInt(userId)],
          readsFrom: {db.usersTable},
        ).getSingleOrNull();
        final cashierName = cashierRow?.data['full_name'] as String?;

        await db.returnAuditLogsDao.insertAuditLog(
          returnType: 'manual',
          productId: productId,
          returnedQuantity: quantity,
          returnedAmount: refundAmount,
          cashierUserId: userId,
          cashierNameSnapshot: cashierName,
          returnReason: reason,
          returnNote: 'استرجاع بدون فاتورة',
          stockBefore: stockBefore,
          stockAfter: stockBefore + quantity,
          referenceType: 'customer_return_items',
          referenceId: itemId,
        );

        // 4. Legacy log entry
        final logDetails = 'Quick Return | Product ID: $productId | Qty: $quantity | Reason: $reason';
        await db.into(db.logsTable).insert(
              LogsTableCompanion.insert(
                userId: Value(userId),
                approvedByUserId: Value(approvedByUserId),
                actionType: 'RETURN_WITHOUT_INVOICE',
                amount: Value(refundAmount),
                details: Value(logDetails),
              ),
            );
      });
    } catch (e, st) {
      debugPrint('[PosSaleService] Error in processQuickReturn: $e\n$st');
      throw Exception('فشل في عملية الاسترجاع السريع: ${e.toString()}');
    }
  }
}
