// lib/core/database/daos/stock_dao.dart
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/stock_ledger_table.dart';
import '../tables/stock_adjustments_table.dart';
import '../tables/products_table.dart';
import '../../constants/movement_types.dart';
import '../../services/stock_guard.dart';

part 'stock_dao.g.dart';

class StockInfo {
  final int productId;
  final double currentStock;
  StockInfo(this.productId, this.currentStock);
}

@DriftAccessor(tables: [StockLedger, StockAdjustments, Products])
class StockDao extends DatabaseAccessor<AppDatabase> with _$StockDaoMixin {
  StockDao(super.db);

  // Get current stock for one product — reads authoritative products.current_stock
  Future<double> getStock(int productId) async {
    final result = await customSelect(
      'SELECT current_stock FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {products},
    ).getSingleOrNull();
    return (result?.data['current_stock'] as num?)?.toDouble() ?? 0.0;
  }

  // Get current stock for all products — reads authoritative products.current_stock
  Future<Map<int, double>> getAllStocks() async {
    final results = await customSelect(
      'SELECT id AS product_id, current_stock AS stock FROM products',
      readsFrom: {products},
    ).get();
    return {
      for (final row in results)
        (row.data['product_id'] as int): (row.data['stock'] as num).toDouble()
    };
  }

  // Watch current stock for one product — reacts to products.current_stock changes
  Stream<double> watchStock(int productId) {
    return customSelect(
      'SELECT current_stock FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {products},
    ).watchSingle().map((row) => (row.data['current_stock'] as num?)?.toDouble() ?? 0.0);
  }

  // Insert a ledger entry
  Future<int> addMovement(StockLedgerCompanion entry) =>
      into(stockLedger).insert(entry);

  // Bulk insert movements
  Future<void> addMovements(List<StockLedgerCompanion> entries) async {
    await batch((b) => b.insertAll(stockLedger, entries));
  }

  // Get ledger history for a product
  Future<List<StockLedgerData>> getProductLedger(int productId) =>
      (select(stockLedger)
        ..where((l) => l.productId.equals(productId))
        ..orderBy([(l) => OrderingTerm.desc(l.createdAt)]))
          .get();

  // Get low stock products — compares products.current_stock directly (no ledger join).
  // current_stock in the result is clamped to 0 via CASE WHEN so callers never
  // receive negative values in the map, keeping display logic simple.
  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    try {
      debugPrint('[StockDao] getLowStockProducts: querying...');
      return await customSelect('''
        SELECT id, name, barcode, min_stock, unit, category_id,
               CASE WHEN current_stock < 0 THEN 0 ELSE current_stock END AS current_stock
        FROM products
        WHERE is_active = 1 AND current_stock <= min_stock
        ORDER BY current_stock ASC
      ''', readsFrom: {products}).get().then(
            (rows) => rows.map((r) => r.data).toList(),
          );
    } catch (e, st) {
      debugPrint('[StockDao] getLowStockProducts error: $e\n$st');
      return [];
    }
  }

  // Reactive stream of low stock products — re-emits whenever products.current_stock changes.
  // current_stock in each emitted map is clamped to 0 (never negative).
  Stream<List<Map<String, dynamic>>> watchLowStockProducts() {
    return customSelect('''
      SELECT id, name, barcode, min_stock, unit, category_id,
             CASE WHEN current_stock < 0 THEN 0 ELSE current_stock END AS current_stock
      FROM products
      WHERE is_active = 1 AND current_stock <= min_stock
      ORDER BY current_stock ASC
    ''', readsFrom: {products}).watch().map(
          (rows) => rows.map((r) => r.data).toList(),
        );
  }

  // Get inventory value report — uses products.current_stock as authoritative source
  Future<List<Map<String, dynamic>>> getInventoryValueReport() async {
    try {
      debugPrint('[StockDao] getInventoryValueReport: querying...');
      final rows = await customSelect('''
        SELECT
          id          AS product_id,
          name        AS product_name,
          barcode,
          cost_price,
          current_stock,
          (current_stock * cost_price) AS total_value
        FROM products
        WHERE is_active = 1 AND current_stock > 0
        ORDER BY total_value DESC
      ''', readsFrom: {products}).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[StockDao] getInventoryValueReport error: $e\n$st');
      return [];
    }
  }

  // Save adjustment and add ledger entry in one transaction
  Future<void> createAdjustment({
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    String note = '',
    int? createdByUserId,
  }) async {
    await transaction(() async {
      final adjId = await into(stockAdjustments).insert(
        StockAdjustmentsCompanion(
          productId: Value(productId),
          adjustmentType: Value(adjustmentType),
          quantityChange: Value(quantityChange),
          reason: Value(reason),
          note: Value(note),
          createdByUserId: Value(createdByUserId),
        ),
      );
      await into(stockLedger).insert(
        StockLedgerCompanion(
          productId: Value(productId),
          movementType: Value(StockMovementType.adjustment.code),
          referenceId: Value(adjId),
          referenceType: const Value('stock_adjustments'),
          quantityChange: Value(quantityChange),
          note: Value('$reason: $note'),
        ),
      );

      // Apply signed delta to current stock.
      // Positive → safe increment; Negative → guarded deduction (never goes below 0).
      if (quantityChange > 0) {
        await customUpdate(
          'UPDATE products SET current_stock = current_stock + ? WHERE id = ?',
          variables: [Variable.withReal(quantityChange), Variable.withInt(productId)],
          updates: {products},
        );
      } else if (quantityChange < 0) {
        await StockGuard.deductStock(
          db: attachedDatabase,
          productId: productId,
          quantity: quantityChange.abs(),
        );
      }
      // quantityChange == 0: no-op, ledger entry already recorded above.
    });
  }

  // Get all adjustments
  Future<List<StockAdjustment>> getAllAdjustments() =>
      (select(stockAdjustments)
        ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
          .get();
}
