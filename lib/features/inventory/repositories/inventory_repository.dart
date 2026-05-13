// lib/features/inventory/repositories/inventory_repository.dart
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../../core/database/app_database.dart';
import '../providers/inventory_provider.dart';

class InventoryRepository {
  final AppDatabase _db;
  InventoryRepository(this._db);

  Future<List<StockOverviewItem>> getStockOverview() async {
    try {
      debugPrint('[InventoryRepository] getStockOverview: fetching products...');
      final products = await _db.productsDao.getAllProducts();
      debugPrint('[InventoryRepository] getStockOverview: found ${products.length} products.');
      return products.map(_toOverviewItem).toList();
    } catch (e, st) {
      debugPrint('[InventoryRepository] getStockOverview error: $e\n$st');
      rethrow;
    }
  }

  /// Reactive stream — re-emits a fresh list whenever products.current_stock changes.
  Stream<List<StockOverviewItem>> watchStockOverview() {
    return _db.productsDao.watchAllProducts().map(
      (rows) => rows.map(_toOverviewItem).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    try {
      debugPrint('[InventoryRepository] getLowStockProducts: querying...');
      return await _db.stockDao.getLowStockProducts();
    } catch (e, st) {
      debugPrint('[InventoryRepository] getLowStockProducts error: $e\n$st');
      rethrow;
    }
  }

  /// Reactive stream — re-emits whenever any product falls below or recovers above min_stock.
  Stream<List<Map<String, dynamic>>> watchLowStockProducts() {
    return _db.stockDao.watchLowStockProducts();
  }

  StockOverviewItem _toOverviewItem(Product p) {
    // Clamp raw DB value to 0 so negative legacy stock never inflates/deflates
    // the displayed total stock value shown in the inventory overview card.
    final safeStock = p.currentStock < 0 ? 0.0 : p.currentStock;
    return StockOverviewItem(
      productId: p.id,
      name: p.name,
      barcode: p.barcode,
      currentStock: p.currentStock,
      minStock: p.minStock,
      unit: p.unit,
      costPrice: p.costPrice,
      sellPrice: p.sellPrice,
      stockValue: safeStock * p.costPrice,
    );
  }

  Future<List<Map<String, dynamic>>> getExpiringProducts(int withinDays) async {
    try {
      debugPrint('[InventoryRepository] getExpiringProducts: withinDays=$withinDays');
      final cutoff = DateTime.now().add(Duration(days: withinDays));
      final results = await _db.customSelect(
        '''SELECT pb.*, p.name as product_name, p.unit
           FROM product_batches pb
           JOIN products p ON p.id = pb.product_id
           WHERE pb.expiry_date <= ?
           ORDER BY pb.expiry_date ASC''',
        variables: [Variable(cutoff)],
        readsFrom: {_db.productBatches, _db.products},
      ).get();
      debugPrint('[InventoryRepository] getExpiringProducts: found ${results.length} items.');
      return results.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[InventoryRepository] getExpiringProducts error: $e\n$st');
      // Return empty list gracefully — expiring products is non-critical
      return [];
    }
  }

  Future<void> createAdjustment({
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    String note = '',
    int? createdByUserId,
  }) async {
    try {
      debugPrint('[InventoryRepository] createAdjustment: product=$productId qty=$quantityChange');
      return await _db.stockDao.createAdjustment(
        productId: productId,
        quantityChange: quantityChange,
        adjustmentType: adjustmentType,
        reason: reason,
        note: note,
        createdByUserId: createdByUserId,
      );
    } catch (e, st) {
      debugPrint('[InventoryRepository] createAdjustment error: $e\n$st');
      rethrow;
    }
  }
}
