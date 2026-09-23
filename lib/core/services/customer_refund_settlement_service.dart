// lib/core/services/customer_refund_settlement_service.dart
//
// Phase C Step 2.1 — Customer credit cash-refund settlement (customer accounting only).
//
// Records actual cash paid to a customer against aggregate customer credit.
// Does NOT modify goods-return (RETURN) semantics.
// Cash Ledger CUSTOMER_REFUND outflow is deferred to a separate step.

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
  unexpectedFailure,
}

class CustomerRefundSettlementException implements Exception {
  const CustomerRefundSettlementException(this.code, this.message);

  final CustomerRefundSettlementFailure code;
  final String message;

  @override
  String toString() => message;
}

/// Low-level REFUND persistence hook used by [CustomerRefundSettlementService].
typedef CustomerRefundInTransaction = Future<void> Function({
  required int customerId,
  required double amount,
  int? returnId,
  String? note,
});

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
  /// When [returnId] is supplied, it is stored on the REFUND row for traceability
  /// after validating the return exists and belongs to [customerId].
  ///
  /// Linked refunds also enforce per-return remaining refundable capacity
  /// (Phase C Step 2.7B).
  Future<void> settleCredit({
    required int customerId,
    required double amount,
    int? returnId,
    String? note,
  }) async {
    const tolerance = 0.0001;

    try {
      await _db.transaction(() async {
        final customer = await _db.customersDao.getCustomerById(customerId);
        if (customer == null) {
          throw CustomerRefundSettlementException(
            CustomerRefundSettlementFailure.customerNotFound,
            'customer not found: $customerId',
          );
        }

        if (amount <= 0) {
          throw CustomerRefundSettlementException(
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
            throw CustomerRefundSettlementException(
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
          throw CustomerRefundSettlementException(
            CustomerRefundSettlementFailure.noCustomerCredit,
            'no customer credit available',
          );
        }

        if (amount > availableCredit + tolerance) {
          throw CustomerRefundSettlementException(
            CustomerRefundSettlementFailure.amountExceedsCredit,
            'settlement exceeds available credit',
          );
        }

        if (_refundInTransactionOverride != null) {
          await _refundInTransactionOverride!(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note,
          );
        } else {
          final inserted = await _db.customerAccountsDao
              .recordRefundInTransactionIfWithinAggregateCredit(
            customerId: customerId,
            amount: amount,
            returnId: returnId,
            note: note ?? '',
            tolerance: tolerance,
          );
          if (!inserted) {
            throw CustomerRefundSettlementException(
              CustomerRefundSettlementFailure.amountExceedsCredit,
              'settlement exceeds available credit (concurrent update)',
            );
          }
        }

        if (returnId != null) {
          final incremented =
              await _db.returnsDao.incrementSettledAmountIfWithinCap(
            returnId: returnId,
            amount: amount,
            creditCap: returnCreditCap!,
          );
          if (!incremented) {
            throw CustomerRefundSettlementException(
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
      });
    } on CustomerRefundSettlementException {
      rethrow;
    } catch (e, st) {
      debugPrint(
        '[CustomerRefundSettlementService] Error in settleCredit: $e\n$st',
      );
      throw const CustomerRefundSettlementException(
        CustomerRefundSettlementFailure.unexpectedFailure,
        'customer refund settlement failed',
      );
    }
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
