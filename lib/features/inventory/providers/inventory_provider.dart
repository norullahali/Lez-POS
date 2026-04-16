// lib/features/inventory/providers/inventory_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../auth/providers/auth_provider.dart';
import '../repositories/inventory_repository.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(AppDatabase.instance);
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

  bool get isLowStock => currentStock <= minStock;
}

class InventoryNotifier extends AsyncNotifier<List<StockOverviewItem>> {
  @override
  Future<List<StockOverviewItem>> build() async {
    try {
      debugPrint('[InventoryNotifier] build: loading stock overview...');
      final result = await ref.watch(inventoryRepositoryProvider).getStockOverview();
      debugPrint('[InventoryNotifier] build: loaded ${result.length} items.');
      return result;
    } catch (e, st) {
      debugPrint('[InventoryNotifier] build error: $e\n$st');
      rethrow;
    }
  }

  Future<void> refresh() {
    ref.invalidateSelf();
    return future;
  }

  Future<void> adjust({
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    String note = '',
  }) async {
    try {
      final userId = ref.read(authProvider).valueOrNull?.user?.id;
      await ref.read(inventoryRepositoryProvider).createAdjustment(
        productId: productId,
        quantityChange: quantityChange,
        adjustmentType: adjustmentType,
        reason: reason,
        note: note,
        createdByUserId: userId,
      );
      ref.invalidateSelf();
    } catch (e, st) {
      debugPrint('[InventoryNotifier] adjust error: $e\n$st');
      rethrow;
    }
  }
}

final inventoryNotifierProvider =
    AsyncNotifierProvider<InventoryNotifier, List<StockOverviewItem>>(InventoryNotifier.new);

// Low stock items
final lowStockProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    debugPrint('[lowStockProvider] loading...');
    return await ref.watch(inventoryRepositoryProvider).getLowStockProducts();
  } catch (e, st) {
    debugPrint('[lowStockProvider] error: $e\n$st');
    rethrow;
  }
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
