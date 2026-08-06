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
import 'package:meta/meta.dart';

import '../database/app_database.dart';
import '../services/stock_guard.dart';

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

class SupplierReturnService {
  final AppDatabase _db;
  final SupplierReturnAccountingPoster? _accountingPoster;

  /// Production constructor — always posts supplier accounting via
  /// [SupplierAccountsDao.recordReturnInTransaction].
  SupplierReturnService(this._db) : _accountingPoster = null;

  /// Test-only constructor for accounting rollback verification (SR.2 test H).
  @visibleForTesting
  SupplierReturnService.withAccountingPoster(
    this._db, {
    required SupplierReturnAccountingPoster accountingPoster,
  }) : _accountingPoster = accountingPoster;

  /// Canonical posting workflow for purchase-linked supplier returns.
  ///
  /// Validates purchase, supplier, items, and returnable quantities inside
  /// one [AppDatabase.transaction], then persists stock and supplier ledger.
  Future<int> postPurchaseLinkedReturn(SupplierReturnPostingInput input) async {
    if (input.lines.isEmpty) {
      throw const SupplierReturnPostingException(
        SupplierReturnPostingFailure.emptyLines,
        'empty lines',
      );
    }

    final aggregated = aggregatePostingLines(input.lines);

    return _db.transaction(() async {
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
        final productName =
            product?.name ?? 'product #${purchaseItem.productId}';
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
              await _db.supplierAccountsDao.recordReturnInTransaction(
                supplierId: input.supplierId,
                amount: accountingTotal,
                returnId: returnId,
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

        return returnId;
      } on InsufficientStockException catch (e) {
        throw SupplierReturnPostingException(
          SupplierReturnPostingFailure.stockInsufficient,
          e.localizedMessage,
        );
      }
    });
  }
}
