import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'manual_return_fingerprint.dart';
import 'manual_return_idempotency_conflict_exception.dart';
import 'manual_return_result.dart';

class _IdempotencySealRace implements Exception {}

/// Service for idempotent manual customer returns (B10).
class ManualReturnService {
  ManualReturnService(this.db);

  final AppDatabase db;

  /// Processes a manual customer return with persistent idempotency (B10).
  Future<ManualReturnResult> processManualReturn({
    required String idempotencyKey,
    required int productId,
    required double quantity,
    required double unitPrice,
    required String reason,
    int? userId,
    int? approvedByUserId,
    @visibleForTesting Future<void> Function()? preSealHook,
  }) async {
    final normalizedReason = ManualReturnFingerprint.normalizeReason(reason);
    final roundedQuantity = ManualReturnFingerprint.roundAmount(quantity);
    final roundedUnitPrice = ManualReturnFingerprint.roundAmount(unitPrice);
    final fingerprintHash = ManualReturnFingerprint.compute(
      productId: productId,
      quantity: roundedQuantity,
      unitPrice: roundedUnitPrice,
      reason: normalizedReason,
      userId: userId,
      approvedByUserId: approvedByUserId,
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.customerManualReturnIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const ManualReturnIdempotencyConflictException();
            }
            return ManualReturnResult(
              customerReturnId: existing.customerReturnId,
              idempotentReplay: true,
            );
          }

          if (roundedQuantity <= 0) {
            throw ArgumentError('Quantity must be positive.');
          }

          final product = await (db.select(db.products)
                ..where((p) => p.id.equals(productId)))
              .getSingleOrNull();
          if (product == null) {
            throw StateError('Product with ID $productId does not exist.');
          }

          final returnNumber = 'RET-${DateTime.now().millisecondsSinceEpoch}';

          final returnId = await db.returnsDao.saveCustomerReturnInTransaction(
            header: CustomerReturnsCompanion(
              returnNumber: Value(returnNumber),
              reason: Value(normalizedReason),
            ),
            items: [
              {
                'productId': productId,
                'productName': product.name,
                'qty': roundedQuantity,
                'price': roundedUnitPrice,
                'discount': 0.0,
              },
            ],
            returnedByUserId: userId,
          );

          if (preSealHook != null) {
            await preSealHook();
          }

          try {
            await db.customerManualReturnIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              productId: productId,
              quantity: roundedQuantity,
              unitPrice: roundedUnitPrice,
              reason: normalizedReason,
              userId: userId,
              approvedByUserId: approvedByUserId,
              customerReturnId: returnId,
            );
          } catch (e) {
            if (_isUniqueManualReturnIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return ManualReturnResult(
            customerReturnId: returnId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on ManualReturnIdempotencyConflictException {
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
        debugPrint(
            '[ManualReturnService] Error in processManualReturn: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('فشل في عملية المرتجع اليدوي: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.customerManualReturnIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return ManualReturnResult(
          customerReturnId: existing.customerReturnId,
          idempotentReplay: true,
        );
      }
      throw const ManualReturnIdempotencyConflictException();
    });
  }

  bool _isUniqueManualReturnIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('customer_manual_return_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}
