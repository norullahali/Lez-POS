import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import '../constants/movement_types.dart';
import '../services/settings_service.dart';
import '../services/stock_guard.dart';
import '../services/credit_limit_exception.dart';
import '../services/invoice_number_service.dart';
import '../services/process_sale_result.dart';
import '../services/pos_sale_idempotency_conflict_exception.dart';
import '../services/quick_return_fingerprint.dart';
import '../services/quick_return_idempotency_conflict_exception.dart';
import '../services/quick_return_result.dart';
import '../../features/loyalty/services/loyalty_service.dart';
import '../activity/activity_categories.dart';
import '../activity/activity_types.dart';
import 'activity_logger_service.dart';

class _IdempotencySealRace implements Exception {}

/// Service to handle POS sales and returns orchestration.
class PosSaleService {
  final AppDatabase db;
  late final LoyaltyService _loyaltyService =
      LoyaltyService(db, SettingsService(db));

  PosSaleService(this.db);

  /// Processes a complete sale transaction.
  /// This method is the single source of truth for POS sales.
  ///
  /// [idempotencyKey] identifies the checkout attempt. Retries with the same key
  /// and identical [fingerprintHash] replay the original sale without mutation.
  ///
  /// Loyalty parameters (optional):
  ///   [pointsUsed]   – points the customer chose to redeem (deducted).
  ///   [netSaleTotal] – the net amount actually paid (used to compute earned pts).
  Future<ProcessSaleResult> processSale({
    required String idempotencyKey,
    required String fingerprintHash,
    required SalesInvoicesCompanion invoice,
    required List<SaleItemsCompanion> items,
    double? debtAmount,
    double pointsUsed = 0,
    double netSaleTotal = 0,
    int? approvedByUserId,
  }) async {
    try {
      for (var attempt = 0; attempt < 8; attempt++) {
        try {
          return await db.transaction(() async {
            final existing = await db.posSaleIdempotencyDao
                .findByIdempotencyKey(idempotencyKey);
            if (existing != null) {
              if (existing.fingerprintHash != fingerprintHash) {
                throw const PosSaleIdempotencyConflictException();
              }
              return ProcessSaleResult(
                invoiceId: existing.salesInvoiceId,
                invoiceNumber: existing.invoiceNumber,
                idempotentReplay: true,
              );
            }

            final result = await _executeNewSaleInTransaction(
              invoice: invoice,
              items: items,
              debtAmount: debtAmount,
              pointsUsed: pointsUsed,
              netSaleTotal: netSaleTotal,
              approvedByUserId: approvedByUserId,
            );

            try {
              await db.posSaleIdempotencyDao.insertCompletedRecord(
                idempotencyKey: idempotencyKey,
                sessionId:
                    invoice.sessionId.present ? invoice.sessionId.value : null,
                fingerprintHash: fingerprintHash,
                salesInvoiceId: result.invoiceId,
                invoiceNumber: result.invoiceNumber,
              );
            } catch (e) {
              if (_isUniqueIdempotencyKeyViolation(e)) {
                throw _IdempotencySealRace();
              }
              rethrow;
            }

            return ProcessSaleResult(
              invoiceId: result.invoiceId,
              invoiceNumber: result.invoiceNumber,
              idempotentReplay: false,
            );
          });
        } on _IdempotencySealRace {
          continue;
        } on PosSaleIdempotencyConflictException {
          rethrow;
        } on CreditLimitExceededException {
          rethrow;
        } catch (e, st) {
          if (_isSqliteBusyOrLocked(e) && attempt < 7) {
            await Future<void>.delayed(
                Duration(milliseconds: 25 * (attempt + 1)));
            continue;
          }
          debugPrint('[PosSaleService] Error in processSale: $e\n$st');
          if (e is CreditLimitExceededException) rethrow;
          if (e is Exception) rethrow;
          throw Exception('فشل في إتمام عملية البيع: ${e.toString()}');
        }
      }

      return await db.transaction(() async {
        final existing =
            await db.posSaleIdempotencyDao.findByIdempotencyKey(idempotencyKey);
        if (existing != null && existing.fingerprintHash == fingerprintHash) {
          return ProcessSaleResult(
            invoiceId: existing.salesInvoiceId,
            invoiceNumber: existing.invoiceNumber,
            idempotentReplay: true,
          );
        }
        throw const PosSaleIdempotencyConflictException();
      });
    } catch (e, st) {
      debugPrint('[PosSaleService] Error in processSale: $e\n$st');
      if (e is CreditLimitExceededException) rethrow;
      if (e is PosSaleIdempotencyConflictException) rethrow;
      if (e is Exception) rethrow;
      throw Exception('فشل في إتمام عملية البيع: ${e.toString()}');
    }
  }

  Future<ProcessSaleResult> _executeNewSaleInTransaction({
    required SalesInvoicesCompanion invoice,
    required List<SaleItemsCompanion> items,
    double? debtAmount,
    required double pointsUsed,
    required double netSaleTotal,
    int? approvedByUserId,
  }) async {
    // 0. Validate Returns and Refund Limits
    final hasReturns =
        items.any((i) => i.quantity.present && i.quantity.value < 0);
    double totalReturnAmount = 0;
    if (hasReturns) {
      totalReturnAmount = items
          .where((i) => i.quantity.present && i.quantity.value < 0)
          .fold(0.0, (s, i) => s + i.total.value.abs());

      final cashierId = invoice.createdByUserId.present
          ? invoice.createdByUserId.value
          : null;
      if (cashierId != null) {
        final cashier = await db.usersDao.getUserById(cashierId);
        if (cashier != null && cashier.roleId != 1) {
          // Skip checks for Admin
          final perms =
              await db.usersDao.getRolePermissionsKeys(cashier.roleId);
          if (!perms.contains('pos.refund')) {
            throw Exception('ليس لديك صلاحية لإجراء المرتجعات.');
          }
          if (totalReturnAmount > cashier.refundLimit) {
            if (approvedByUserId == null) {
              throw Exception(
                  'تجاوزت الحد المسموح للمرتجع. يتطلب الأمر موافقة مشرف.');
            }
          }
        }
      }
    }

    // 1. Allocate invoice number atomically, then insert SalesInvoice record.
    final allocatedInvoiceNumber =
        await InvoiceNumberService(db).allocateNextInTransaction();
    final invoiceToInsert = invoice.copyWith(
      invoiceNumber: Value(allocatedInvoiceNumber),
    );
    final invoiceId = await db.into(db.salesInvoices).insert(invoiceToInsert);

    await ActivityLoggerService(db).logInfo(
      activityType: ActivityTypes.invoiceCreated,
      category: ActivityCategories.sales,
      action: 'create',
      title: 'إنشاء فاتورة',
      entityType: 'invoice',
      entityId: invoiceId,
      metadata: {
        'invoiceNumber': allocatedInvoiceNumber,
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
      if (customerId != null && customerId != 1) {
        // 1 = General Customer
        final saleNote = 'فاتورة رقم $allocatedInvoiceNumber';
        final insertedId = await db.customerAccountsDao
            .recordSaleInTransactionIfWithinCreditLimit(
          customerId: customerId,
          amount: debtAmount,
          invoiceId: invoiceId,
          note: saleNote,
        );
        if (insertedId == null) {
          final currentBalance = await db.customerAccountsDao
              .calculateBalanceFromTransactions(customerId);
          final customerRow = await (db.select(db.customers)
                ..where((c) => c.id.equals(customerId)))
              .getSingleOrNull();
          throw CreditLimitExceededException(
            customerId: customerId,
            currentBalance: currentBalance,
            creditLimit: customerRow?.creditLimit ?? 0,
            requestedAmount: debtAmount,
          );
        }
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
    final approvalText =
        approvedByUserId != null ? ' | Approved By: $approvedByUserId' : '';
    await db.into(db.logsTable).insert(LogsTableCompanion.insert(
          userId: Value(
              invoice.processedByUserId.value ?? invoice.createdByUserId.value),
          approvedByUserId: Value(approvedByUserId),
          actionType: hasReturns ? 'SALE_WITH_RETURN' : 'SALE_CONFIRMED',
          amount: Value(hasReturns ? totalReturnAmount : invoice.total.value),
          details:
              Value('Invoice ID: $invoiceId (Ref: $invoiceId)$approvalText'),
        ));

    return ProcessSaleResult(
      invoiceId: invoiceId,
      invoiceNumber: allocatedInvoiceNumber,
    );
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('pos_sale_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }

  /// Processes a quick return without an original invoice (B9 idempotent).
  ///
  /// [idempotencyKey] identifies the operation. Retries with the same key and
  /// identical parameters replay the original return without mutation.
  Future<QuickReturnResult> processQuickReturn({
    required String idempotencyKey,
    required int productId,
    required double quantity,
    required double refundAmount,
    required int userId,
    required String reason,
    int? approvedByUserId,
    @visibleForTesting Future<void> Function()? preSealHook,
  }) async {
    final normalizedReason = QuickReturnFingerprint.normalizeReason(reason);
    final roundedQuantity = QuickReturnFingerprint.roundAmount(quantity);
    final roundedRefundAmount =
        QuickReturnFingerprint.roundAmount(refundAmount);
    final fingerprintHash = QuickReturnFingerprint.compute(
      productId: productId,
      quantity: roundedQuantity,
      refundAmount: roundedRefundAmount,
      reason: normalizedReason,
      userId: userId,
      approvedByUserId: approvedByUserId,
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.customerQuickReturnIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const QuickReturnIdempotencyConflictException();
            }
            return QuickReturnResult(
              customerReturnId: existing.customerReturnId,
              idempotentReplay: true,
            );
          }

          if (roundedQuantity <= 0) {
            throw ArgumentError('Quantity must be positive.');
          }
          if (roundedRefundAmount < 0) {
            throw ArgumentError('Refund amount must be non-negative.');
          }

          final product = await (db.select(db.products)
                ..where((p) => p.id.equals(productId)))
              .getSingleOrNull();
          if (product == null) {
            throw StateError('Product with ID $productId does not exist.');
          }

          final stockBefore = await db.stockDao.getStock(productId);
          final returnNumber =
              'RET-QUICK-${DateTime.now().millisecondsSinceEpoch}';

          final returnId = await db.into(db.customerReturns).insert(
                CustomerReturnsCompanion.insert(
                  originalInvoiceId: const Value(null),
                  returnNumber: returnNumber,
                  total: Value(roundedRefundAmount),
                  reason: Value(normalizedReason),
                  returnDate: Value(DateTime.now()),
                ),
              );

          final itemId = await db.into(db.customerReturnItems).insert(
                CustomerReturnItemsCompanion.insert(
                  returnId: returnId,
                  productId: productId,
                  productName: product.name,
                  quantity: roundedQuantity,
                  unitPrice: roundedQuantity > 0
                      ? roundedRefundAmount / roundedQuantity
                      : 0,
                  unitCost: Value(product.costPrice),
                  total: roundedRefundAmount,
                ),
              );

          await db.into(db.stockLedger).insert(
                StockLedgerCompanion.insert(
                  productId: productId,
                  movementType: StockMovementType.returnIn.code,
                  referenceId: Value(itemId),
                  referenceType: const Value('customer_return_items'),
                  quantityChange: roundedQuantity,
                  unitCost: Value(product.costPrice),
                ),
              );

          await db.customUpdate(
            'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
            variables: [
              Variable.withReal(roundedQuantity),
              Variable.withInt(productId),
            ],
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
            returnedQuantity: roundedQuantity,
            returnedAmount: roundedRefundAmount,
            cashierUserId: userId,
            cashierNameSnapshot: cashierName,
            returnReason: normalizedReason,
            returnNote: 'استرجاع بدون فاتورة',
            stockBefore: stockBefore,
            stockAfter: stockBefore + roundedQuantity,
            referenceType: 'customer_return_items',
            referenceId: itemId,
          );

          final logDetails =
              'Quick Return | Product ID: $productId | Qty: $roundedQuantity | Reason: $normalizedReason';
          await db.into(db.logsTable).insert(
                LogsTableCompanion.insert(
                  userId: Value(userId),
                  approvedByUserId: Value(approvedByUserId),
                  actionType: 'RETURN_WITHOUT_INVOICE',
                  amount: Value(roundedRefundAmount),
                  details: Value(logDetails),
                ),
              );

          if (preSealHook != null) {
            await preSealHook();
          }

          try {
            await db.customerQuickReturnIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              productId: productId,
              quantity: roundedQuantity,
              refundAmount: roundedRefundAmount,
              userId: userId,
              approvedByUserId: approvedByUserId,
              customerReturnId: returnId,
            );
          } catch (e) {
            if (_isUniqueQuickReturnIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return QuickReturnResult(
            customerReturnId: returnId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on QuickReturnIdempotencyConflictException {
        rethrow;
      } on ArgumentError {
        rethrow;
      } on StateError {
        rethrow;
      } catch (e, st) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('[PosSaleService] Error in processQuickReturn: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('فشل في عملية الاسترجاع السريع: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.customerQuickReturnIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return QuickReturnResult(
          customerReturnId: existing.customerReturnId,
          idempotentReplay: true,
        );
      }
      throw const QuickReturnIdempotencyConflictException();
    });
  }

  bool _isUniqueQuickReturnIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('customer_quick_return_idempotency');
  }
}
