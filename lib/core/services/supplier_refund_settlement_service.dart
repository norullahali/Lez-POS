// lib/core/services/supplier_refund_settlement_service.dart
//
// SR.3.3 Step 1 — Supplier credit cash-refund settlement (supplier accounting only).
// SR Step 2.1 — Persistent idempotency for REFUND settlement.
//
// Records actual cash received from a supplier against aggregate supplier credit.
// Does NOT modify goods-return (RETURN) semantics.
// Cash Ledger SUPPLIER_REFUND inflow is derived from committed REFUND rows.

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

enum SupplierRefundSettlementFailure {
  supplierNotFound,
  noSupplierCredit,
  invalidAmount,
  amountExceedsCredit,
  returnNotFound,
  returnSupplierMismatch,
  idempotencyKeyConflict,
  unexpectedFailure,
}

class SupplierRefundSettlementException implements Exception {
  const SupplierRefundSettlementException(this.code, this.message);

  final SupplierRefundSettlementFailure code;
  final String message;

  @override
  String toString() => message;
}

class SupplierRefundSettlementResult {
  const SupplierRefundSettlementResult({
    required this.supplierTransactionId,
    required this.idempotentReplay,
  });

  final int supplierTransactionId;
  final bool idempotentReplay;
}

/// Low-level REFUND persistence hook used by [SupplierRefundSettlementService].
typedef RefundInTransaction = Future<int> Function({
  required int supplierId,
  required double amount,
  int? returnId,
  String? note,
});

class _IdempotencySealRace implements Exception {}

/// Canonical service for settling supplier credit via cash received (REFUND txn).
class SupplierRefundSettlementService {
  SupplierRefundSettlementService(
    this._db, {
    @visibleForTesting RefundInTransaction? refundInTransactionOverride,
    @visibleForTesting Future<void> Function()? postRefundHook,
  })  : _refundInTransactionOverride = refundInTransactionOverride,
        _postRefundHook = postRefundHook;

  final AppDatabase _db;
  final RefundInTransaction? _refundInTransactionOverride;
  final Future<void> Function()? _postRefundHook;

  /// Consumes [amount] of aggregate supplier credit for [supplierId].
  ///
  /// [idempotencyKey] identifies the operation. Retries with the same key and
  /// identical parameters replay the original successful REFUND without mutation.
  Future<SupplierRefundSettlementResult> settleCredit({
    required int supplierId,
    required double amount,
    required String idempotencyKey,
    int? returnId,
    String? note,
  }) async {
    const tolerance = 0.0001;
    final normalizedNote = (note ?? '').trim();

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await _db.transaction(() async {
          final existing = await _db.supplierRefundIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (!_fingerprintMatches(
              existing,
              supplierId: supplierId,
              amount: amount,
              returnId: returnId,
              normalizedNote: normalizedNote,
              tolerance: tolerance,
            )) {
              throw const SupplierRefundSettlementException(
                SupplierRefundSettlementFailure.idempotencyKeyConflict,
                'idempotency key reused with different parameters',
              );
            }
            return SupplierRefundSettlementResult(
              supplierTransactionId: existing.supplierTransactionId,
              idempotentReplay: true,
            );
          }

          final supplier = await _db.suppliersDao.getSupplierById(supplierId);
          if (supplier == null) {
            throw SupplierRefundSettlementException(
              SupplierRefundSettlementFailure.supplierNotFound,
              'supplier not found: $supplierId',
            );
          }

          if (amount <= 0) {
            throw const SupplierRefundSettlementException(
              SupplierRefundSettlementFailure.invalidAmount,
              'settlement amount must be positive',
            );
          }

          if (returnId != null) {
            final header = await _db.returnsDao.getSupplierReturnById(returnId);
            if (header == null) {
              throw SupplierRefundSettlementException(
                SupplierRefundSettlementFailure.returnNotFound,
                'supplier return not found: $returnId',
              );
            }
            final returnSupplierId = header.supplierId;
            if (returnSupplierId == null || returnSupplierId != supplierId) {
              throw SupplierRefundSettlementException(
                SupplierRefundSettlementFailure.returnSupplierMismatch,
                'supplier return $returnId does not belong to supplier $supplierId',
              );
            }
          }

          final balance = await _db.supplierAccountsDao
              .calculateBalanceFromTransactions(supplierId);
          final availableCredit = balance < 0 ? -balance : 0.0;

          if (availableCredit <= 0) {
            throw const SupplierRefundSettlementException(
              SupplierRefundSettlementFailure.noSupplierCredit,
              'no supplier credit available',
            );
          }

          if (amount > availableCredit + tolerance) {
            throw const SupplierRefundSettlementException(
              SupplierRefundSettlementFailure.amountExceedsCredit,
              'settlement exceeds available credit',
            );
          }

          final int supplierTransactionId;
          if (_refundInTransactionOverride != null) {
            supplierTransactionId = await _refundInTransactionOverride!(
              supplierId: supplierId,
              amount: amount,
              returnId: returnId,
              note: note,
            );
          } else {
            final insertedId = await _db.supplierAccountsDao
                .recordRefundInTransactionIfWithinAggregateCredit(
              supplierId: supplierId,
              amount: amount,
              returnId: returnId,
              note: normalizedNote,
              tolerance: tolerance,
            );
            if (insertedId == null) {
              throw const SupplierRefundSettlementException(
                SupplierRefundSettlementFailure.amountExceedsCredit,
                'settlement exceeds available credit (concurrent update)',
              );
            }
            supplierTransactionId = insertedId;
          }

          if (_postRefundHook != null) {
            await _postRefundHook!();
          }

          await _db.logsDao.insertLog(
            userId: null,
            actionType: 'SUPPLIER_REFUND',
            details:
                'Cash refund of $amount from supplier ${supplier.name} (Ref: $supplierId${returnId != null ? ', return: $returnId' : ''})',
          );

          try {
            await _db.supplierRefundIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              supplierId: supplierId,
              amount: amount,
              returnId: returnId,
              note: normalizedNote,
              supplierTransactionId: supplierTransactionId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return SupplierRefundSettlementResult(
            supplierTransactionId: supplierTransactionId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on SupplierRefundSettlementException {
        rethrow;
      } catch (e, st) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        debugPrint(
          '[SupplierRefundSettlementService] Error in settleCredit: $e\n$st',
        );
        throw const SupplierRefundSettlementException(
          SupplierRefundSettlementFailure.unexpectedFailure,
          'supplier refund settlement failed',
        );
      }
    }

    return _db.transaction(() async {
      final existing = await _db.supplierRefundIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null &&
          _fingerprintMatches(
            existing,
            supplierId: supplierId,
            amount: amount,
            returnId: returnId,
            normalizedNote: normalizedNote,
            tolerance: tolerance,
          )) {
        return SupplierRefundSettlementResult(
          supplierTransactionId: existing.supplierTransactionId,
          idempotentReplay: true,
        );
      }
      throw const SupplierRefundSettlementException(
        SupplierRefundSettlementFailure.idempotencyKeyConflict,
        'idempotency key reused with different parameters',
      );
    });
  }

  bool _fingerprintMatches(
    SupplierRefundIdempotencyData existing, {
    required int supplierId,
    required double amount,
    required int? returnId,
    required String normalizedNote,
    required double tolerance,
  }) {
    if (existing.supplierId != supplierId) return false;
    if ((existing.amount - amount).abs() > tolerance) return false;
    if (existing.returnId != returnId) return false;
    if (existing.note != normalizedNote) return false;
    return true;
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('supplier_refund_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}
