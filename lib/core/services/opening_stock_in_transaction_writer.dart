import 'package:drift/drift.dart';

import '../constants/movement_types.dart';
import '../database/app_database.dart';

/// Internal opening stock executor - only [OpeningStockSaveService] may use this.
class OpeningStockInTransactionWriter {
  OpeningStockInTransactionWriter(this._db);

  final AppDatabase _db;

  /// In-transaction live activity guard (I2).
  Future<bool> hasLiveInventoryActivity(int productId) async {
    final result = await _db.customSelect(
      "SELECT 1 FROM stock_ledger WHERE product_id = ? AND movement_type != 'OPENING' LIMIT 1",
      variables: [Variable.withInt(productId)],
      readsFrom: {_db.stockLedger},
    ).getSingleOrNull();
    return result != null;
  }

  /// Inserts opening stock for one product. Must run inside caller transaction.
  /// Does not DELETE existing OPENING rows (I5).
  Future<void> insertOpeningStock({
    required int productId,
    required double quantity,
    required double unitCost,
    required int createdBy,
  }) async {
    final stockBefore = await _db.stockDao.getStock(productId);

    await _db.stockDao.addMovement(
      StockLedgerCompanion(
        productId: Value(productId),
        movementType: Value(StockMovementType.opening.code),
        referenceType: const Value('opening'),
        quantityChange: Value(quantity),
        unitCost: Value(unitCost),
        note: const Value('\u0631\u0635\u064a\u062f \u0627\u0641\u062a\u062a\u0627\u062d\u064a'),
      ),
    );

    await _db.customUpdate(
      'UPDATE products SET current_stock = ? WHERE id = ?',
      variables: [Variable.withReal(quantity), Variable.withInt(productId)],
      updates: {_db.products},
    );

    await _db.stockMovementsDao.recordMovement(
      productId: productId,
      movementType: StockMovementKind.openingStock,
      quantityChange: quantity - stockBefore,
      stockBefore: stockBefore,
      stockAfter: quantity,
      referenceType: 'opening_stock',
      note: '\u0631\u0635\u064a\u062f \u0627\u0641\u062a\u062a\u0627\u062d\u064a',
      createdByUserId: createdBy,
    );
  }
}
