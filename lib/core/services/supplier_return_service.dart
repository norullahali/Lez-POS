// lib/core/services/supplier_return_service.dart
//
// SR.2 — Atomic purchase-linked supplier return posting workflow.
//
// **Canonical production entry point** for NEW purchase-linked supplier returns:
// [SupplierReturnService.postPurchaseLinkedReturn].
//
// SR.3 UI must call this service — NOT [ReturnsDao.saveSupplierReturn].
//
// Architecture:
//   UI → SupplierReturnService → ONE transaction → DAOs

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../database/daos/returns_dao.dart';
import '../services/stock_guard.dart';
import 'supplier_return_fingerprint.dart';
import 'supplier_return_idempotency_conflict_exception.dart';
import 'supplier_return_posting_result.dart';

class SupplierReturnPostingLine {
  final int purchaseItemId;
  final double quantity;

  const SupplierReturnPostingLine({
    required this.purchaseItemId,
    required this.quantity,
  });
}

class SupplierReturnPostingInput {
  final int supplierId;
  final int purchaseInvoiceId;
  final List<SupplierReturnPostingLine> lines;
  final DateTime? returnDate;
  final String? notes;
  final String? reason;
  final String? returnNumber;

  const SupplierReturnPostingInput({
    required this.supplierId,
    required this.purchaseInvoiceId,
    required this.lines,
    this.returnDate,
    this.notes,
    this.reason,
    this.returnNumber,
  });
}

enum SupplierReturnPostingFailure {
  purchaseNotFound,
  supplierNotFound,
  supplierMismatch,
  emptyLines,
  purchaseItemNotFound,
  purchaseItemInvoiceMismatch,
  invalidQuantity,
  quantityExceedsReturnable,
  stockInsufficient,
  supplierAccountingFailure,
}

class SupplierReturnPostingException implements Exception {
  final SupplierReturnPostingFailure code;
  final String message;

  const SupplierReturnPostingException(this.code, this.message);

  @override
  String toString() => message;
}

Map<int, double> aggregatePostingLines(List<SupplierReturnPostingLine> lines) {
  final aggregated = <int, double>{};
  for (final line in lines) {
    aggregated[line.purchaseItemId] =
        (aggregated[line.purchaseItemId] ?? 0) + line.quantity;
  }
  return aggregated;
}

typedef SupplierReturnAccountingPoster = Future<void> Function({
  required int supplierId,
  required double amount,
  required int returnId,
  String note,
});

class _IdempotencySealRace implements Exception {}

class _PurchaseLinkedReturnExecution {
  const _PurchaseLinkedReturnExecution({
    required this.supplierReturnId,
    required this.supplierTransactionId,
  });

  final int supplierReturnId;
  final int? supplierTransactionId;
}

class SupplierReturnService {
  final AppDatabase _db;
  final SupplierReturnAccountingPoster? _accountingPoster;
  final Future<void> Function()? _preSealHook;

  /// Production constructor — always posts supplier accounting via
  /// [SupplierAccountsDao.recordReturnInTransaction].
  SupplierReturnService(
    this._db, {
    @visibleForTesting Future<void> Function()? preSealHook,
  })  : _accountingPoster = null,
        _preSealHook = preSealHook;

  /// Test-only constructor for accounting rollback verification (SR.2 test H).
  @visibleForTesting
  SupplierReturnService.withAccountingPoster(
    this._db, {
    required SupplierReturnAccountingPoster accountingPoster,
    Future<void> Function()? preSealHook,
  })  : _accountingPoster = accountingPoster,
        _preSealHook = preSealHook;

  /// Canonical posting workflow for purchase-linked supplier returns.
  ///
  /// Validates purchase, supplier, items, and returnable quantities inside
  /// one [AppDatabase.transaction], then persists stock and supplier ledger.
  Future<SupplierReturnPostingResult> postPurchaseLinkedReturn({
    required String idempotencyKey,
    required SupplierReturnPostingInput input,
  }) async {
    if (input.lines.isEmpty) {
      throw const SupplierReturnPostingException(
        SupplierReturnPostingFailure.emptyLines,
        'empty lines',
      );
    }

    final fingerprintHash = SupplierReturnFingerprint.compute(input);

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        return await _db.transaction(() async {
          final existing = await _db.supplierReturnIdempotencyDao
              .findByIdempotencyKey(idempotencyKey);
          if (existing != null) {
            if (existing.fingerprintHash != fingerprintHash) {
              throw const SupplierReturnIdempotencyConflictException();
            }
            return SupplierReturnPostingResult(
              supplierReturnId: existing.supplierReturnId,
              supplierTransactionId: existing.supplierTransactionId,
              idempotentReplay: true,
            );
          }

          final execution =
              await _executePurchaseLinkedReturnInTransaction(input);

          if (_preSealHook != null) {
            await _preSealHook!();
          }

          try {
            await _db.supplierReturnIdempotencyDao.insertCompletedRecord(
              idempotencyKey: idempotencyKey,
              fingerprintHash: fingerprintHash,
              supplierId: input.supplierId,
              purchaseInvoiceId: input.purchaseInvoiceId,
              supplierReturnId: execution.supplierReturnId,
              supplierTransactionId: execution.supplierTransactionId,
            );
          } catch (e) {
            if (_isUniqueIdempotencyKeyViolation(e)) {
              throw _IdempotencySealRace();
            }
            rethrow;
          }

          return SupplierReturnPostingResult(
            supplierReturnId: execution.supplierReturnId,
            supplierTransactionId: execution.supplierTransactionId,
            idempotentReplay: false,
          );
        });
      } on _IdempotencySealRace {
        continue;
      } on SupplierReturnIdempotencyConflictException {
        rethrow;
      } on SupplierReturnPostingException {
        rethrow;
      } catch (e, st) {
        if (_isSqliteBusyOrLocked(e) && attempt < 7) {
          await Future<void>.delayed(
            Duration(milliseconds: 25 * (attempt + 1)),
          );
          continue;
        }
        debugPrint(
            '[SupplierReturnService] Error in postPurchaseLinkedReturn: $e\n$st');
        if (e is Exception) rethrow;
        throw Exception('فشل في حفظ مرتجع المورد: ${e.toString()}');
      }
    }

    return _db.transaction(() async {
      final existing = await _db.supplierReturnIdempotencyDao
          .findByIdempotencyKey(idempotencyKey);
      if (existing != null && existing.fingerprintHash == fingerprintHash) {
        return SupplierReturnPostingResult(
          supplierReturnId: existing.supplierReturnId,
          supplierTransactionId: existing.supplierTransactionId,
          idempotentReplay: true,
        );
      }
      throw const SupplierReturnIdempotencyConflictException();
    });
  }

  Future<_PurchaseLinkedReturnExecution>
      _executePurchaseLinkedReturnInTransaction(
    SupplierReturnPostingInput input,
  ) async {
    final aggregated = aggregatePostingLines(input.lines);

    final purchase =
        await _db.purchasesDao.getInvoiceById(input.purchaseInvoiceId);
    if (purchase == null) {
      throw SupplierReturnPostingException(
        SupplierReturnPostingFailure.purchaseNotFound,
        'purchase not found: ${input.purchaseInvoiceId}',
      );
    }

    final supplier = await _db.suppliersDao.getSupplierById(input.supplierId);
    if (supplier == null) {
      throw SupplierReturnPostingException(
        SupplierReturnPostingFailure.supplierNotFound,
        'supplier not found: ${input.supplierId}',
      );
    }

    if (purchase.supplierId != input.supplierId) {
      throw SupplierReturnPostingException(
        SupplierReturnPostingFailure.supplierMismatch,
        'supplier mismatch for purchase ${input.purchaseInvoiceId}',
      );
    }

    final persistItems = <Map<String, dynamic>>[];
    var accountingTotal = 0.0;

    for (final entry in aggregated.entries) {
      final purchaseItemId = entry.key;
      final requestedQty = entry.value;

      if (requestedQty <= 0) {
        throw SupplierReturnPostingException(
          SupplierReturnPostingFailure.invalidQuantity,
          'invalid quantity for purchase item $purchaseItemId',
        );
      }

      final purchaseItem =
          await _db.purchasesDao.getPurchaseItemById(purchaseItemId);
      if (purchaseItem == null) {
        throw SupplierReturnPostingException(
          SupplierReturnPostingFailure.purchaseItemNotFound,
          'purchase item not found: $purchaseItemId',
        );
      }

      if (purchaseItem.invoiceId != input.purchaseInvoiceId) {
        throw SupplierReturnPostingException(
          SupplierReturnPostingFailure.purchaseItemInvoiceMismatch,
          'purchase item $purchaseItemId invoice mismatch',
        );
      }

      final returnable = await _db.returnsDao
          .getReturnableQuantityForPurchaseItem(purchaseItemId);
      if (requestedQty > returnable + 0.0001) {
        throw SupplierReturnPostingException(
          SupplierReturnPostingFailure.quantityExceedsReturnable,
          'quantity exceeds returnable for purchase item $purchaseItemId',
        );
      }

      final product = await (_db.select(_db.products)
            ..where((p) => p.id.equals(purchaseItem.productId)))
          .getSingleOrNull();
      final productName = product?.name ?? 'product #${purchaseItem.productId}';
      final unitCost = purchaseItem.unitCost;
      accountingTotal += requestedQty * unitCost;

      persistItems.add({
        'purchaseItemId': purchaseItemId,
        'productId': purchaseItem.productId,
        'productName': productName,
        'qty': requestedQty,
        'cost': unitCost,
      });
    }

    final returnNumber =
        input.returnNumber ?? 'SR-${DateTime.now().microsecondsSinceEpoch}';

    final header = SupplierReturnsCompanion(
      supplierId: Value(input.supplierId),
      purchaseInvoiceId: Value(input.purchaseInvoiceId),
      returnNumber: Value(returnNumber),
      returnDate: input.returnDate != null
          ? Value(input.returnDate!)
          : const Value.absent(),
      total: Value(accountingTotal),
      reason:
          input.reason != null ? Value(input.reason!) : const Value.absent(),
      notes: input.notes != null ? Value(input.notes!) : const Value.absent(),
    );

    int? supplierTransactionId;

    try {
      final returnId = await _db.returnsDao.persistSupplierReturn(
        header: header,
        items: persistItems,
      );

      if (accountingTotal > 0) {
        try {
          if (_accountingPoster != null) {
            await _accountingPoster!(
              supplierId: input.supplierId,
              amount: accountingTotal,
              returnId: returnId,
              note: input.notes ?? '',
            );
          } else {
            supplierTransactionId = await _db.supplierAccountsDao
                .recordReturnInTransactionIfWithinPurchaseInvoiceCreditCap(
              supplierId: input.supplierId,
              purchaseInvoiceId: input.purchaseInvoiceId,
              proposedAmount: accountingTotal,
              referenceId: returnId,
              note: input.notes ?? '',
            );
          }
        } catch (_) {
          throw const SupplierReturnPostingException(
            SupplierReturnPostingFailure.supplierAccountingFailure,
            'supplier accounting failed',
          );
        }
      }

      return _PurchaseLinkedReturnExecution(
        supplierReturnId: returnId,
        supplierTransactionId: supplierTransactionId,
      );
    } on InsufficientStockException catch (e) {
      throw SupplierReturnPostingException(
        SupplierReturnPostingFailure.stockInsufficient,
        e.localizedMessage,
      );
    } on SupplierReturnQuantityCapExceededException catch (_) {
      throw const SupplierReturnPostingException(
        SupplierReturnPostingFailure.quantityExceedsReturnable,
        'quantity exceeds returnable for purchase item',
      );
    }
  }

  bool _isUniqueIdempotencyKeyViolation(Object error) {
    final message = error.toString();
    return message.contains('UNIQUE constraint failed') &&
        message.contains('supplier_return_idempotency');
  }

  bool _isSqliteBusyOrLocked(Object error) {
    final message = error.toString();
    return message.contains('database is locked') ||
        message.contains('SqliteException(5)');
  }
}
