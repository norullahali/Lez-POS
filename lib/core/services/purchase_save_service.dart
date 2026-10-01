import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'purchase_idempotency_conflict_exception.dart';
import 'purchase_save_result.dart';

class _IdempotencySealRace implements Exception {}

/// Canonical orchestrator for purchase save with persistent idempotency (B7).
class PurchaseSaveService {
  PurchaseSaveService(
    this.db, {
    @visibleForTesting Future<void> Function()? preSealHook,
  }) : _preSealHook = preSealHook;

  final AppDatabase db;
  final Future<void> Function()? _preSealHook;

  /// Processes a complete purchase save with idempotency.
  ///
  /// [operatorInvoiceNumber] empty/null means auto-generate inside the transaction.
  Future<PurchaseSaveResult> processSave({
    required String idempotencyKey,
    required String fingerprintHash,
    required int? supplierId,
    required String operatorInvoiceNumber,
    required DateTime purchaseDate,
    required double invoiceDiscount,
    required double total,
    required double paidAmount,
    required DateTime? dueDate,
    required String notes,
    required List<Map<String, dynamic>> items,
    int? createdByUserId,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.purchaseIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const PurchaseIdempotencyConflictException();
            }
            return PurchaseSaveResult(
              purchaseInvoiceId: existing.purchaseInvoiceId,
              purchaseInvoiceNumber: existing.invoiceNumber,
              idempotentReplay: true,
            );
          }

          await _validatePurchase(
            supplierId: supplierId,
            items: items,
            total: total,
            paidAmount: paidAmount,
          );

          final trimmedOperatorNumber = operatorInvoiceNumber.trim();
          final resolvedInvoiceNumber = trimmedOperatorNumber.isEmpty
              ? 'PUR-${DateTime.now().millisecondsSinceEpoch}'
              : trimmedOperatorNumber;
          final debtAmount = total - paidAmount;

          final invoiceId =
              await db.purchasesDao.savePurchaseInvoiceInTransaction(
            header: PurchaseInvoicesCompanion(
              supplierId: Value(supplierId),
              invoiceNumber: Value(resolvedInvoiceNumber),
              purchaseDate: Value(purchaseDate),
              subtotal: Value(_computeSubtotal(items)),
              discountAmount: Value(invoiceDiscount),
              total: Value(total),
              paidAmount: Value(paidAmount),
              debtAmount: Value(debtAmount),
              dueDate: Value(dueDate),
              status: const Value('CONFIRMED'),
              notes: Value(notes.trim()),
              createdByUserId: Value(createdByUserId),
            ),
            items: items,
          );

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.purchaseIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              supplierId: supplierId,
              fingerprintHash: fingerprintHash,
              purchaseInvoiceId: invoiceId,
              invoiceNumber: resolvedInvoiceNumber,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return PurchaseSaveResult(
            purchaseInvoiceId: invoiceId,
            purchaseInvoiceNumber: resolvedInvoiceNumber,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on PurchaseIdempotencyConflictException {
        rethrow;
      } on ArgumentError {
        rethrow;
      } catch (e, st) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        debugPrint('[PurchaseSaveService] Error in processSave: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('فشل في حفظ فاتورة المشتريات: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing =
          await db.purchaseIdempotencyDao.findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return PurchaseSaveResult(
          purchaseInvoiceId: existing.purchaseInvoiceId,
          purchaseInvoiceNumber: existing.invoiceNumber,
          idempotentReplay: true,
        );
      }
      throw const PurchaseIdempotencyConflictException();
    });
  }

  Future<void> _validatePurchase({
    required int? supplierId,
    required List<Map<String, dynamic>> items,
    required double total,
    required double paidAmount,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Purchase must contain at least one item.');
    }
    if (total < 0) {
      throw ArgumentError('Purchase total cannot be negative.');
    }
    if (paidAmount < 0) {
      throw ArgumentError('Paid amount cannot be negative.');
    }
    if (paidAmount > total + 0.000001) {
      throw ArgumentError('Paid amount cannot exceed purchase total.');
    }

    if (supplierId != null) {
      final supplier = await db.suppliersDao.getSupplierById(supplierId);
      if (supplier == null) {
        throw Exception('Supplier with ID $supplierId does not exist.');
      }
    }

    for (final item in items) {
      final productId = item['productId'] as int;
      final qty = (item['qty'] as num).toDouble();
      final cost = (item['cost'] as num).toDouble();

      if (qty <= 0) {
        throw ArgumentError('Product $productId has invalid quantity.');
      }
      if (cost <= 0) {
        throw ArgumentError('Product $productId has invalid unit cost.');
      }

      final product = await db.productsDao.getProductById(productId);
      if (product == null) {
        throw Exception('Product with ID $productId does not exist.');
      }
    }
  }

  double _computeSubtotal(List<Map<String, dynamic>> items) {
    return items.fold<double>(0, (sum, item) {
      final qty = (item['qty'] as num).toDouble();
      final cost = (item['cost'] as num).toDouble();
      return sum + (qty * cost);
    });
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('purchase_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}
