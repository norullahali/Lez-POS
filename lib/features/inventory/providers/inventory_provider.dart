// lib/features/inventory/providers/inventory_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/stock_adjustment_save_fingerprint.dart';
import '../../../core/services/stock_adjustment_save_result.dart';
import '../repositories/inventory_repository.dart';
import 'stock_adjustment_save_service_provider.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(
    AppDatabase.instance,
    ref.read(stockAdjustmentSaveServiceProvider),
  );
});

class StockOverviewItem {
  final int productId;
  final String name;
  final String barcode;
  final double currentStock;
  final double minStock;
  final String unit;
  final double costPrice;
  final double sellPrice;
  final double stockValue;

  const StockOverviewItem({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.currentStock,
    required this.minStock,
    required this.unit,
    required this.costPrice,
    required this.sellPrice,
    required this.stockValue,
  });

  /// Clamps raw DB value to 0; historical negative values never appear in UI.
  double get safeStock => currentStock < 0 ? 0 : currentStock;

  bool get isLowStock => safeStock <= minStock;
}

/// Reactive notifier — auto-updates whenever products.current_stock changes in the DB.
class InventoryNotifier extends StreamNotifier<List<StockOverviewItem>> {
  @override
  Stream<List<StockOverviewItem>> build() {
    debugPrint('[InventoryNotifier] build: watching stock overview stream...');
    return ref.watch(inventoryRepositoryProvider).watchStockOverview();
  }

  Future<void> refresh() {
    ref.invalidateSelf();
    return future;
  }

  Future<StockAdjustmentSaveResult> adjust({
    required String idempotencyKey,
    required String fingerprintHash,
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    String note = '',
    required int createdBy,
  }) async {
    try {
      return await ref.read(inventoryRepositoryProvider).saveAdjustment(
            idempotencyKey: idempotencyKey,
            fingerprintHash: fingerprintHash,
            productId: productId,
            quantityChange: quantityChange,
            adjustmentType: adjustmentType,
            reason: reason,
            note: note,
            createdBy: createdBy,
          );
    } catch (e, st) {
      debugPrint('[InventoryNotifier] adjust error: $e\n$st');
      rethrow;
    }
  }

  String computeFingerprint({
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    String note = '',
    required int createdBy,
  }) {
    return StockAdjustmentSaveFingerprint.compute(
      productId: productId,
      quantityChange: quantityChange,
      adjustmentType: adjustmentType,
      reason: reason,
      note: note,
      createdBy: createdBy,
    );
  }
}

final inventoryNotifierProvider =
    StreamNotifierProvider<InventoryNotifier, List<StockOverviewItem>>(InventoryNotifier.new);

// Low stock items — reactive stream, re-evaluates whenever any current_stock changes
final lowStockProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  debugPrint('[lowStockProvider] watching low-stock stream...');
  return ref.watch(inventoryRepositoryProvider).watchLowStockProducts();
});

// Expiring products
final expiringProductsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    debugPrint('[expiringProductsProvider] loading...');
    return await ref.watch(inventoryRepositoryProvider).getExpiringProducts(30);
  } catch (e, st) {
    debugPrint('[expiringProductsProvider] error: $e\n$st');
    rethrow;
  }
});
