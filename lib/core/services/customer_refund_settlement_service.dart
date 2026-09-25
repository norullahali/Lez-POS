// lib/core/services/customer_refund_settlement_service.dart
//
// Phase C Step 2.1 — Customer credit cash-refund settlement (customer accounting only).
// Phase C Step 3.0 — Persistent idempotency for REFUND settlement.

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

enum CustomerRefundSettlementFailure {
  customerNotFound,
  noCustomerCredit,
  invalidAmount,
  amountExceedsCredit,
  noReturnRefundableAmount,
  amountExceedsReturnRefundableAmount,
  returnNotFound,
  returnCustomerMismatch,
  idempotencyKeyConflict,
  unexpectedFailure,
}

class CustomerRefundSettlementException implements Exception {
  const CustomerRefundSettlementException(this.code, this.message);

  final CustomerRefundSettlementFailure code;
  final String message;

  @override
  String toString() => message;
}

class CustomerRefundSettlementResult {
  const CustomerRefundSettlementResult({
    required this.customerTransactionId,
    required this.idempotentReplay,
  });

  final int customerTransactionId;
  final bool idempotentReplay;
}

/// Low-level REFUND persistence hook used by [CustomerRefundSettlementService].
typedef CustomerRefundInTransaction = Future<int> Function({
  required int customerId,
  required double amount,
  int? returnId,
  String? note,
});

class _IdempotencySealRace implements Exception {}

/// Canonical service for settling customer credit via cash paid (REFUND txn).
class CustomerRefundSettlementService {
  CustomerRefundSettlementService(
    this._db, {
    @visibleForTesting CustomerRefundInTransaction? refundInTransactionOverride,
    @visibleForTesting Future<void> Function()? postRefundHook,
  })  : _refundInTransactionOverride = refundInTransactionOverride,
        _postRefundHook = postRefundHook;

  final AppDatabase _db;
  final CustomerRefundInTransaction? _refundInTransactionOverride;
  final Future<void> Function()? _postRefundHook;

  /// Consumes [amount] of aggregate customer credit for [customerId].
  ///
  /// [idempotencyKey] identifies the operation. Retries with the same key and
  /// identical parameters replay the original successful REFUND without mutation.
  Future<CustomerRefundSettlementResult> settleCredit({
    required int customerId,
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
          final existing = await _db.customerRefundIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (!_fingerprintMatches(
              existing,
              customerId: customerId,
              amount: amount,
              returnId: returnId,
              normalizedNote: normalizedNote,
              tolerance: tolerance,
            )) {
              throw const CustomerRefundSettlementException(
                CustomerRefundSettlementFailure.idempotencyKeyConflict,
                'idempotency key reused with different parameters',
              );
            }
            return CustomerRefundSettlementResult(
              customerTransactionId: existing.customerTransactionId,
              idempotentReplay: true,
            );
          }

          final customer = await _db.customersDao.getCustomerById(customerId);
          if (customer == null) {
            throw CustomerRefundSettlementException(
              CustomerRefundSettlementFailure.customerNotFound,
              'customer not found: $customerId',
            );
          }

          if (amount <= 0) {
            throw const CustomerRefundSettlementException(
              CustomerRefundSettlementFailure.invalidAmount,
              'settlement amount must be positive',
            );
          }

          double? returnCreditCap;
          if (returnId != null) {
            final returnCustomerId = await _resolveReturnCustomerId(returnId);
            if (returnCustomerId == null) {
              throw CustomerRefundSettlementException(
                CustomerRefundSettlementFailure.returnNotFound,
                'customer return not found: $returnId',
              );
            }
            if (returnCustomerId != customerId) {
              throw CustomerRefundSettlementException(
                CustomerRefundSettlementFailure.returnCustomerMismatch,
                'customer return $returnId does not belong to customer $customerId',
              );
            }

            final header = await _db.returnsDao.getCustomerReturnById(returnId);
            final originalInvoiceId = header!.originalInvoiceId!;

            returnCreditCap = await _db.customerAccountsDao
                .getCreditReversalTotalForSaleInvoice(
              customerId: customerId,
              invoiceId: originalInvoiceId,
            );

            final settledAmount = await _db.returnsDao
                    .getSettledAmountForCustomerReturn(returnId) ??
                0.0;
            final remainingReturnRefund = returnCreditCap - settledAmount;

            if (remainingReturnRefund <= tolerance) {
              throw CustomerRefundSettlementException(
                CustomerRefundSettlementFailure.noReturnRefundableAmount,
                'no return refundable amount remaining for return $returnId',
              );
            }

            if (amount > remainingReturnRefund + tolerance) {
              throw const CustomerRefundSettlementException(
                CustomerRefundSettlementFailure
                    .amountExceedsReturnRefundableAmount,
                'settlement exceeds remaining return refundable amount',
              );
            }
          }

          final balance =
              await _db.customerAccountsDao.calculateBalanceFromTransactions(
            customerId,
          );
          final availableCredit = balance < 0 ? -balance : 0.0;

          if (availableCredit <= 0) {
            throw const CustomerRefundSettlementException(
              CustomerRefundSettlementFailure.noCustomerCredit,
              'no customer credit available',
            );
          }

          if (amount > availableCredit + tolerance) {
            throw const CustomerRefundSettlementException(
              CustomerRefundSettlementFailure.amountExceedsCredit,
              'settlement exceeds available credit',
            );
          }

          final int customerTransactionId;
          if (_refundInTransactionOverride != null) {
            customerTransactionId = await _refundInTransactionOverride!(
              customerId: customerId,
              amount: amount,
              returnId: returnId,
              note: note,
            );
          } else {
            final insertedId = await _db.customerAccountsDao
                .recordRefundInTransactionIfWithinAggregateCredit(
              customerId: customerId,
              amount: amount,
              returnId: returnId,
              note: normalizedNote,
              tolerance: tolerance,
            );
            if (insertedId == null) {
              throw const CustomerRefundSettlementException(
                CustomerRefundSettlementFailure.amountExceedsCredit,
                'settlement exceeds available credit (concurrent update)',
              );
            }
            customerTransactionId = insertedId;
          }

          if (returnId != null) {
            final incremented =
                await _db.returnsDao.incrementSettledAmountIfWithinCap(
              returnId: returnId,
              amount: amount,
              creditCap: returnCreditCap!,
            );
            if (!incremented) {
              throw const CustomerRefundSettlementException(
                CustomerRefundSettlementFailure
                    .amountExceedsReturnRefundableAmount,
                'settlement exceeds return refundable amount (concurrent update)',
              );
            }
          }

          if (_postRefundHook != null) {
            await _postRefundHook!();
          }

          await _db.logsDao.insertLog(
            userId: null,
            actionType: 'CUSTOMER_REFUND',
            details:
                'Cash refund of $amount to customer ${customer.name} (Ref: $customerId${returnId != null ? ', return: $returnId' : ''})',
          );

          try {
            await _db.customerRefundIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              customerId: customerId,
              amount: amount,
              returnId: returnId,
              note: normalizedNote,
              customerTransactionId: customerTransactionId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return CustomerRefundSettlementResult(
            customerTransactionId: customerTransactionId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on CustomerRefundSettlementException {
        rethrow;
      } catch (e, st) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
              Duration(milliseconds: 25 * (attempt + 1)));
          continue;
        }
        debugPrint(
          '[CustomerRefundSettlementService] Error in settleCredit: $e\n$st',
        );
        throw const CustomerRefundSettlementException(
          CustomerRefundSettlementFailure.unexpectedFailure,
          'customer refund settlement failed',
        );
      }
    }

    return _db.transaction(() async {
      final existing = await _db.customerRefundIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null &&
          _fingerprintMatches(
            existing,
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            normalizedNote: normalizedNote,
            tolerance: tolerance,
          )) {
        return CustomerRefundSettlementResult(
          customerTransactionId: existing.customerTransactionId,
          idempotentReplay: true,
        );
      }
      throw const CustomerRefundSettlementException(
        CustomerRefundSettlementFailure.idempotencyKeyConflict,
        'idempotency key reused with different parameters',
      );
    });
  }

  bool _fingerprintMatches(
    CustomerRefundIdempotencyData existing, {
    required int customerId,
    required double amount,
    required int? returnId,
    required String normalizedNote,
    required double tolerance,
  }) {
    if (existing.customerId != customerId) return false;
    if ((existing.amount - amount).abs() > tolerance) return false;
    if (existing.returnId != returnId) return false;
    if (existing.note != normalizedNote) return false;
    return true;
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('customer_refund_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }

  /// Derives the owning customer for a [customer_returns] row via invoice linkage.
  Future<int?> _resolveReturnCustomerId(int returnId) async {
    final header = await (_db.select(_db.customerReturns)
          ..where((r) => r.id.equals(returnId)))
        .getSingleOrNull();
    if (header == null) return null;

    final invoiceId = header.originalInvoiceId;
    if (invoiceId == null) return null;

    final invoice = await _db.salesDao.getInvoiceById(invoiceId);
    return invoice?.customerId;
  }
}
