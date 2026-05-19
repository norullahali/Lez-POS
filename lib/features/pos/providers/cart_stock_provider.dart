// lib/features/pos/providers/cart_stock_provider.dart
//
// Centralized in-memory available-stock helpers.
// availableStock = product.currentStock (DB cache) - cartReservedQty (all open carts)
// Nothing is ever written to the database from here.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pos_provider.dart';
import 'pos_products_provider.dart';

/// Maps productId to total quantity reserved across ALL open carts.
/// Free items and return lines are excluded.
/// Re-computes synchronously on every cart mutation - no DB access.
final cartReservedQtyProvider = Provider<Map<int, double>>((ref) {
  final cartState = ref.watch(cartProvider);
  final map = <int, double>{};
  for (final cart in cartState.carts.values) {
    for (final item in cart.items) {
      if (item.isFreeItem || item.isReturn) continue;
      final id = item.product.id;
      if (id != null) map[id] = (map[id] ?? 0) + item.quantity;
    }
  }
  return map;
});

/// Effective available stock = DB currentStock - all-carts reserved qty.
/// Clamped to >= 0. Per-product .family ensures only affected cards rebuild.
final availableStockProvider = Provider.family<double, int>((ref, productId) {
  final posState = ref.watch(posProductsProvider).valueOrNull;
  if (posState == null) return 0.0;
  final dbStock = posState.productsMap[productId]?.currentStock ?? 0.0;
  final reserved = ref.watch(cartReservedQtyProvider)[productId] ?? 0.0;
  return (dbStock - reserved).clamp(0.0, double.infinity);
});

/// true when no more units of this product can be added to any cart.
final isOutOfStockProvider = Provider.family<bool, int>((ref, productId) {
  return ref.watch(availableStockProvider(productId)) <= 0;
});
