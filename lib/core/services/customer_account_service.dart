import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'customer_payment_idempotency_conflict_exception.dart';
import 'customer_payment_result.dart';

class _IdempotencySealRace implements Exception {}

/// Service for managing customer accounts and debt.
class CustomerAccountService {
  CustomerAccountService(
    this.db, {
    @visibleForTesting Future<void> Function()? preSealHook,
  }) : _preSealHook = preSealHook;

  final AppDatabase db;
  final Future<void> Function()? _preSealHook;

  /// Processes a payment from a customer with persistent idempotency (B6).
  ///
  /// [idempotencyKey] identifies the operation. Retries with the same key and
  /// identical parameters replay the original PAYMENT without mutation.
  Future<CustomerPaymentResult> processPayment({
    required String idempotencyKey,
    required int customerId,
    required double amount,
    String? note,
  }) async {
    const tolerance = 0.0001;
    final normalizedNote = (note ?? '').trim();

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await db.transaction(() async {
          final existing = await db.customerPaymentIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (!_parametersMatch(
              existing,
              customerId: customerId,
              amount: amount,
              normalizedNote: normalizedNote,
              tolerance: tolerance,
            )) {
              throw const CustomerPaymentIdempotencyConflictException();
            }
            return CustomerPaymentResult(
              customerTransactionId: existing.customerTransactionId,
              idempotentReplay: true,
            );
          }

          if (amount <= 0) {
            throw ArgumentError('Payment amount must be positive.');
          }

          final customer = await db.customersDao.getCustomerById(customerId);
          if (customer == null) {
            throw Exception('Customer with ID $customerId does not exist.');
          }

          final customerTransactionId =
              await db.customerAccountsDao.recordPaymentInTransaction(
            customerId: customerId,
            amount: amount,
            note: normalizedNote,
          );

          await db.logsDao.insertLog(
            userId: null,
            actionType: 'CUSTOMER_PAYMENT',
            details:
                'Payment of $amount from ${customer.name} (Ref: $customerId)',
          );

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await db.customerPaymentIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              customerId: customerId,
              amount: amount,
              note: normalizedNote,
              customerTransactionId: customerTransactionId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return CustomerPaymentResult(
            customerTransactionId: customerTransactionId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on CustomerPaymentIdempotencyConflictException {
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
        debugPrint('[CustomerAccountService] Error in processPayment: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('فشل في معالجة دفعة العميل: ${e.toString()}');
      }
    }

    return db.transaction(() async {
      final existing = await db.customerPaymentIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null &&
          _parametersMatch(
            existing,
            customerId: customerId,
            amount: amount,
            normalizedNote: normalizedNote,
            tolerance: tolerance,
          )) {
        return CustomerPaymentResult(
          customerTransactionId: existing.customerTransactionId,
          idempotentReplay: true,
        );
      }
      throw const CustomerPaymentIdempotencyConflictException();
    });
  }

  bool _parametersMatch(
    CustomerPaymentIdempotencyData existing, {
    required int customerId,
    required double amount,
    required String normalizedNote,
    required double tolerance,
  }) {
    if (existing.customerId != customerId) return false;
    if ((existing.amount - amount).abs() > tolerance) return false;
    if (existing.note != normalizedNote) return false;
    return true;
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('customer_payment_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }

  /// Manually adjusts a customer's debt balance.
  Future<void> adjustCustomerBalance({
    required int customerId,
    required double adjustment,
    required String reason,
  }) async {
    if (adjustment == 0) throw ArgumentError('Adjustment amount cannot be zero.');
    if (reason.isEmpty) throw ArgumentError('Adjustment reason is required.');

    try {
      await db.transaction(() async {
        final customer = await db.customersDao.getCustomerById(customerId);
        if (customer == null) {
          throw Exception('Customer with ID $customerId does not exist.');
        }

        await db.customerAccountsDao.adjustBalance(
          customerId: customerId,
          signedAmount: adjustment,
          reason: reason,
        );

        await db.logsDao.insertLog(
          userId: null,
          actionType: 'CUSTOMER_ADJUSTMENT',
          details:
              'Balance adjusted by $adjustment. Reason: $reason (Ref: $customerId)',
        );
      });
    } catch (e, st) {
      debugPrint(
          '[CustomerAccountService] Error in adjustCustomerBalance: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في تعديل رصيد العميل: ${e.toString()}');
    }
  }
}
