// lib/core/services/supplier_refund_settlement_service.dart
//
// SR.3.3 Step 1 â€” Supplier credit cash-refund settlement (supplier accounting only).
//
// Records actual cash received from a supplier against aggregate supplier credit.
// Does NOT modify goods-return (RETURN) semantics or Cash Ledger integration.

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

enum SupplierRefundSettlementFailure {
  supplierNotFound,
  noSupplierCredit,
  invalidAmount,
  amountExceedsCredit,
  returnNotFound,
  returnSupplierMismatch,
  unexpectedFailure,
}

class SupplierRefundSettlementException implements Exception {
  const SupplierRefundSettlementException(this.code, this.message);

  final SupplierRefundSettlementFailure code;
  final String message;

  @override
  String toString() => message;
}

/// Canonical service for settling supplier credit via cash received (REFUND txn).
class SupplierRefundSettlementService {
  SupplierRefundSettlementService(this._db);

  final AppDatabase _db;

  /// Consumes [amount] of aggregate supplier credit for [supplierId].
  ///
  /// When [returnId] is supplied, it is stored on the REFUND row for traceability
  /// after validating the return exists and belongs to [supplierId].
  Future<void> settleCredit({
    required int supplierId,
    required double amount,
    int? returnId,
    String? note,
  }) async {
    try {
      await _db.transaction(() async {
        final supplier = await _db.suppliersDao.getSupplierById(supplierId);
        if (supplier == null) {
          throw SupplierRefundSettlementException(
            SupplierRefundSettlementFailure.supplierNotFound,
            'supplier not found: $supplierId',
          );
        }

        if (amount <= 0) {
          throw SupplierRefundSettlementException(
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
          throw SupplierRefundSettlementException(
            SupplierRefundSettlementFailure.noSupplierCredit,
            'no supplier credit available',
          );
        }

        if (amount > availableCredit + 0.0001) {
          throw SupplierRefundSettlementException(
            SupplierRefundSettlementFailure.amountExceedsCredit,
            'settlement exceeds available credit',
          );
        }

        await _db.supplierAccountsDao.recordRefundInTransaction(
          supplierId: supplierId,
          amount: amount,
          returnId: returnId,
          note: note ?? '',
        );

        await _db.logsDao.insertLog(
          userId: null,
          actionType: 'SUPPLIER_REFUND',
          details:
              'Cash refund of $amount from supplier ${supplier.name} (Ref: $supplierId${returnId != null ? ', return: $returnId' : ''})',
        );
      });
    } on SupplierRefundSettlementException {
      rethrow;
    } catch (e, st) {
      debugPrint(
        '[SupplierRefundSettlementService] Error in settleCredit: $e\n$st',
      );
      throw const SupplierRefundSettlementException(
        SupplierRefundSettlementFailure.unexpectedFailure,
        'supplier refund settlement failed',
      );
    }
  }
}
