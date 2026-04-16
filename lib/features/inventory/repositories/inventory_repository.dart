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
      debugPrint('[InventoryRepository] getStockOverview: fetching products + stocks...');
      final products = await _db.productsDao.getAllProducts();
      final stocks = await _db.stockDao.getAllStocks();
      debugPrint('[InventoryRepository] getStockOverview: found ${products.length} products.');
      return products.map((p) {
        final stock = stocks[p.id] ?? 0.0;
        return StockOverviewItem(
          productId: p.id,
          name: p.name,
          barcode: p.barcode,
          currentStock: stock,
          minStock: p.minStock,
          unit: p.unit,
          costPrice: p.costPrice,
          sellPrice: p.sellPrice,
          stockValue: stock * p.costPrice,
        );
      }).toList();
    } catch (e, st) {
      debugPrint('[InventoryRepository] getStockOverview error: $e\n$st');
      rethrow;
    }
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
