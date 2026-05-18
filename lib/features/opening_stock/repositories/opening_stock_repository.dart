// lib/features/opening_stock/repositories/opening_stock_repository.dart
import 'package:drift/drift.dart';
import '../../../core/constants/movement_types.dart';
import '../../../core/database/app_database.dart';

class OpeningStockRepository {
  final AppDatabase _db;
  OpeningStockRepository(this._db);

  /// Check if a product already has an opening stock entry
  Future<bool> hasOpeningEntry(int productId) async {
    final result = await _db.customSelect(
      "SELECT COUNT(*) as cnt FROM stock_ledger WHERE product_id = ? AND movement_type = 'OPENING'",
      variables: [Variable.withInt(productId)],
      readsFrom: {_db.stockLedger},
    ).getSingleOrNull();
    return ((result?.data['cnt'] as int?) ?? 0) > 0;
  }

  /// Save opening stock — sets current_stock directly and records an OPENING ledger entry,
  /// plus a high-level [StockMovements] record.
  Future<void> saveOpeningStock(int productId, double quantity, double unitCost) async {
    // Remove existing opening ledger entry if any (keeps audit trail clean).
    await _db.customStatement(
      "DELETE FROM stock_ledger WHERE product_id = ? AND movement_type = 'OPENING'",
      [productId],
    );

    // Insert fresh opening ledger entry (low-level audit trail).
    await _db.stockDao.addMovement(
      StockLedgerCompanion(
        productId: Value(productId),
        movementType: Value(StockMovementType.opening.code),
        referenceType: const Value('opening'),
        quantityChange: Value(quantity),
        unitCost: Value(unitCost),
        note: const Value('رصيد افتتاحي'),
      ),
    );

    // Read current stock BEFORE the authoritative write.
    final stockBefore = await _db.stockDao.getStock(productId);

    // Set current_stock directly — authoritative write for opening stock.
    await _db.customUpdate(
      'UPDATE products SET current_stock = ? WHERE id = ?',
      variables: [Variable.withReal(quantity), Variable.withInt(productId)],
      updates: {_db.products},
    );

    // Record high-level movement (signed delta = new qty − old qty).
    await _db.stockMovementsDao.recordMovement(
      productId: productId,
      movementType: StockMovementKind.openingStock,
      quantityChange: quantity - stockBefore,
      stockBefore: stockBefore,
      stockAfter: quantity,
      referenceType: 'opening_stock',
      note: 'رصيد افتتاحي',
    );
  }

  /// Save opening stock for multiple products.
  Future<void> saveBulkOpeningStock(List<Map<String, dynamic>> entries) async {
    for (final entry in entries) {
      await saveOpeningStock(
        entry['productId'] as int,
        (entry['quantity'] as num).toDouble(),
        (entry['cost'] as num?)?.toDouble() ?? 0.0,
      );
    }
  }
}
