import 'package:drift/drift.dart';

import '../constants/movement_types.dart';
import '../database/app_database.dart';
import 'stock_guard.dart';

/// Internal stock adjustment executor - only [StockAdjustmentSaveService] may use this.
class StockAdjustmentInTransactionWriter {
  StockAdjustmentInTransactionWriter(this._db);

  final AppDatabase _db;

  /// Applies one stock adjustment. Must run inside caller transaction.
  Future<int> applyAdjustmentInTransaction({
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    required String note,
    required int createdByUserId,
  }) async {
    final adjId = await _db.into(_db.stockAdjustments).insert(
          StockAdjustmentsCompanion(
            productId: Value(productId),
            adjustmentType: Value(adjustmentType),
            quantityChange: Value(quantityChange),
            reason: Value(reason),
            note: Value(note),
            createdByUserId: Value(createdByUserId),
          ),
        );

    await _db.into(_db.stockLedger).insert(
          StockLedgerCompanion(
            productId: Value(productId),
            movementType: Value(StockMovementType.adjustment.code),
            referenceId: Value(adjId),
            referenceType: const Value('stock_adjustments'),
            quantityChange: Value(quantityChange),
            note: Value('$reason: $note'),
          ),
        );

    if (quantityChange > 0) {
      await _db.customUpdate(
        'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
        variables: [
          Variable.withReal(quantityChange),
          Variable.withInt(productId),
        ],
        updates: {_db.products},
      );
    } else if (quantityChange < 0) {
      await StockGuard.deductStock(
        db: _db,
        productId: productId,
        quantity: quantityChange.abs(),
      );
    }

    return adjId;
  }
}
