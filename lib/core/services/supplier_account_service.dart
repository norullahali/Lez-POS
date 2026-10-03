import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'supplier_payment_exceeds_payable_exception.dart';
import 'supplier_payment_fingerprint.dart';
import 'supplier_payment_idempotency_conflict_exception.dart';
import 'supplier_payment_result.dart';

class _IdempotencySealRace implements Exception {}

/// Service to handle supplier accounts and supplier debt transactions.
class SupplierAccountService {
  SupplierAccountService(
    this.db, {
    @visibleForTesting Future<void> Function()? preSealHook,
  }) : _preSealHook = preSealHook;

  final AppDatabase db;
  final Future<void> Function()? _preSealHook;

  /// Processes a payment to a supplier with persistent idempotency (B8).
  ///
  /// [idempotencyKey] identifies the operation. Retries with the same key and
  /// identical parameters replay the original PAYMENT without mutation.
  Future<SupplierPaymentResult> processPayment({
    required String idempotencyKey,
    required int supplierId,
    required double amount,
    String? note,
  }) async {
    final canonicalNote = SupplierPaymentFingerprint.normalizeNote(note);
    final roundedAmount = SupplierPaymentFingerprint.roundAmount(amount);
    final fingerprintHash = SupplierPaymentFingerprint.compute(
      supplierId: supplierId,
      amount: roundedAmount,
      note: canonicalNote,
    );

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.supplierPaymentIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const SupplierPaymentIdempotencyConflictException();
            }
            return SupplierPaymentResult(
              supplierTransactionId: existing.supplierTransactionId,
              idempotentReplay: true,
            );
          }

          if (amount <= 0) {
            throw ArgumentError('Payment amount must be positive.');
          }

          final supplier = await db.suppliersDao.getSupplierById(supplierId);
          if (supplier == null) {
            throw Exception('Supplier with ID $supplierId does not exist.');
          }

          final insertedId = await db.supplierAccountsDao
              .recordPaymentInTransactionIfWithinPayable(
            supplierId: supplierId,
            amount: roundedAmount,
            note: canonicalNote,
          );
          if (insertedId == null) {
            final currentPayable = await db.supplierAccountsDao
                .calculateBalanceFromTransactions(supplierId);
            throw SupplierPaymentExceedsPayableException(
              supplierId: supplierId,
              currentPayable: currentPayable,
              requestedAmount: roundedAmount,
            );
          }

          await db.logsDao.insertLog(
            userId: null, // TODO: Integration with auth service
            actionType: 'SUPPLIER_PAYMENT',
            details:
                'Payment of $roundedAmount to supplier ${supplier.name} (Ref: $supplierId)',
          );

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.supplierPaymentIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              supplierId: supplierId,
              amount: roundedAmount,
              note: canonicalNote,
              supplierTransactionId: insertedId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return SupplierPaymentResult(
            supplierTransactionId: insertedId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on SupplierPaymentIdempotencyConflictException {
        rethrow;
      } on SupplierPaymentExceedsPayableException {
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
        debugPrint('[SupplierAccountService] Error in processPayment: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('فشل في معالجة دفعة المورد: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.supplierPaymentIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return SupplierPaymentResult(
          supplierTransactionId: existing.supplierTransactionId,
          idempotentReplay: true,
        );
      }
      throw const SupplierPaymentIdempotencyConflictException();
    });
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('supplier_payment_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}
