// lib/core/database/daos/stock_dao.dart
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/stock_ledger_table.dart';
import '../tables/stock_adjustments_table.dart';
import '../tables/products_table.dart';
import '../../constants/movement_types.dart';

part 'stock_dao.g.dart';

class StockInfo {
  final int productId;
  final double currentStock;
  StockInfo(this.productId, this.currentStock);
}

@DriftAccessor(tables: [StockLedger, StockAdjustments, Products])
class StockDao extends DatabaseAccessor<AppDatabase> with _$StockDaoMixin {
  StockDao(super.db);

  // Get current stock for one product
  Future<double> getStock(int productId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(quantity_change), 0.0) as stock FROM stock_ledger WHERE product_id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {stockLedger},
    ).getSingleOrNull();
    return (result?.data['stock'] as num?)?.toDouble() ?? 0.0;
  }

  // Get stock for all products
  Future<Map<int, double>> getAllStocks() async {
    final results = await customSelect(
      'SELECT product_id, COALESCE(SUM(quantity_change), 0.0) as stock FROM stock_ledger GROUP BY product_id',
      readsFrom: {stockLedger},
    ).get();
    return {
      for (final row in results)
        (row.data['product_id'] as int): (row.data['stock'] as num).toDouble()
    };
  }

  // Watch stock for one product
  Stream<double> watchStock(int productId) {
    return customSelect(
      'SELECT COALESCE(SUM(quantity_change), 0.0) as stock FROM stock_ledger WHERE product_id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {stockLedger},
    ).watchSingle().map((row) => (row.data['stock'] as num?)?.toDouble() ?? 0.0);
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

  // Get low stock products (stock < min_stock)
  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    try {
      debugPrint('[StockDao] getLowStockProducts: querying...');
      return await customSelect('''
        SELECT p.id, p.name, p.barcode, p.min_stock, p.unit, p.category_id,
               COALESCE(SUM(sl.quantity_change), 0) as current_stock
        FROM products p
        LEFT JOIN stock_ledger sl ON sl.product_id = p.id
        WHERE p.is_active = 1
        GROUP BY p.id
        HAVING current_stock < p.min_stock
        ORDER BY current_stock ASC
      ''', readsFrom: {products, stockLedger}).get().then(
            (rows) => rows.map((r) => r.data).toList(),
          );
    } catch (e, st) {
      debugPrint('[StockDao] getLowStockProducts error: $e\n$st');
      return [];
    }
  }

  // Get inventory value report
  Future<List<Map<String, dynamic>>> getInventoryValueReport() async {
    try {
      debugPrint('[StockDao] getInventoryValueReport: querying...');
      final rows = await customSelect('''
        SELECT 
          p.id as product_id, 
          p.name as product_name,
          p.barcode,
          p.cost_price,
          COALESCE(SUM(sl.quantity_change), 0) as current_stock,
          (COALESCE(SUM(sl.quantity_change), 0) * p.cost_price) as total_value
        FROM products p
        LEFT JOIN stock_ledger sl ON sl.product_id = p.id
        WHERE p.is_active = 1
        GROUP BY p.id
        HAVING current_stock > 0
        ORDER BY total_value DESC
      ''', readsFrom: {products, stockLedger}).get();
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
    });
  }

  // Get all adjustments
  Future<List<StockAdjustment>> getAllAdjustments() =>
      (select(stockAdjustments)
        ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
          .get();
}
