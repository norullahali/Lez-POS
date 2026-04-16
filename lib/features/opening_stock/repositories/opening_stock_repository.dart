// lib/features/opening_stock/repositories/opening_stock_repository.dart
import '../../../core/database/app_database.dart';
import '../../../core/constants/movement_types.dart';
import 'package:drift/drift.dart';

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

  /// Save opening stock - creates a OPENING ledger entry
  Future<void> saveOpeningStock(int productId, double quantity, double unitCost) async {
    // Remove existing opening entry if any
    await _db.customStatement(
      "DELETE FROM stock_ledger WHERE product_id = ? AND movement_type = 'OPENING'",
      [productId],
    );
    // Insert fresh opening entry
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
