import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../constants/movement_types.dart';
import '../services/settings_service.dart';
import '../../features/loyalty/services/loyalty_service.dart';

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

        // 2. Process items using batch for performance
        await db.batch((batch) {
          for (final item in items) {
            // Add sale item to batch
            final itemWithInvoice = item.copyWith(invoiceId: Value(invoiceId));
            batch.insert(db.saleItems, itemWithInvoice);

            // Add stock ledger entry to batch
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

  /// Processes a customer return against an original invoice.
  Future<int> processReturn({
    required int invoiceId,
    required List<SaleItemsCompanion> returnedItems,
    double? refundAmount,
  }) async {
    try {
      return await db.transaction(() async {
        // 1. Validate Original Invoice
        final originalInvoice = await (db.select(db.salesInvoices)
              ..where((i) => i.id.equals(invoiceId)))
            .getSingleOrNull();

        if (originalInvoice == null) {
          throw Exception('Original invoice with ID $invoiceId does not exist.');
        }

        final customerId = originalInvoice.customerId;

        // 2. Generate Return Header
        final returnNumber = 'RTN-${originalInvoice.invoiceNumber}-${DateTime.now().millisecondsSinceEpoch}';
        double totalReturnValue = 0;
        for (final item in returnedItems) {
          totalReturnValue += item.quantity.value * item.unitPrice.value;
        }

        final returnId = await db.into(db.customerReturns).insert(
              CustomerReturnsCompanion(
                originalInvoiceId: Value(invoiceId),
                returnNumber: Value(returnNumber),
                total: Value(totalReturnValue),
                returnDate: Value(DateTime.now()),
              ),
            );

        // 3. Process Items and Stock with batch for performance
        final productIds = returnedItems.map((i) => i.productId.value).toSet().toList();
        final products = await (db.select(db.products)
              ..where((p) => p.id.isIn(productIds)))
            .get();
        final productMap = {for (var p in products) p.id: p.name};

        await db.batch((batch) {
          for (final item in returnedItems) {
            final name = productMap[item.productId.value] ?? 'Unknown Product';
            batch.insert(
              db.customerReturnItems,
              CustomerReturnItemsCompanion(
                returnId: Value(returnId),
                productId: item.productId,
                productName: Value(name),
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                unitCost: item.unitCost,
                total: Value(item.quantity.value * item.unitPrice.value),
              ),
            );

            batch.insert(
              db.stockLedger,
              StockLedgerCompanion(
                productId: item.productId,
                movementType: Value(StockMovementType.returnIn.code),
                referenceType: const Value('customer_return_items'),
                quantityChange: item.quantity,
                unitCost: item.unitCost,
              ),
            );
          }
        });

        // 5. Update CustomerAccount balance if refundAmount is provided
        if (refundAmount != null && refundAmount > 0 && customerId != null && customerId != 1) {
          await db.customerAccountsDao.recordReturn(
            customerId: customerId,
            amount: refundAmount,
            returnId: returnId,
            note: 'مرتجع فاتورة رقم ${originalInvoice.invoiceNumber}',
          );
        }

        // 6. Logging
        await db.logsDao.insertLog(
          userId: null,
          actionType: 'SALE_RETURN',
          details: 'Return ID: $returnId for Invoice ID: $invoiceId (Ref: $invoiceId)',
        );

        return returnId;
      });
    } catch (e, st) {
      debugPrint('[PosSaleService] Error in processReturn: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في عملية المرتجع: ${e.toString()}');
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

        // 2. Insert CustomerReturnItems record
        await db.into(db.customerReturnItems).insert(
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

        // 3. Update stock ledger
        await db.into(db.stockLedger).insert(
              StockLedgerCompanion.insert(
                productId: productId,
                movementType: StockMovementType.returnIn.code,
                referenceType: const Value('customer_return_items'),
                quantityChange: quantity, // Positive
                unitCost: Value(product.costPrice),
              ),
            );

        // 4. Audit Log
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
