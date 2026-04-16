// lib/features/products/providers/products_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../pos/providers/pos_products_provider.dart';
import '../models/product_model.dart';
import '../repositories/products_repository.dart';

final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  return ProductsRepository(AppDatabase.instance);
});

final productsStreamProvider = StreamProvider<List<ProductModel>>((ref) {
  return ref.watch(productsRepositoryProvider).watchAll();
});

class ProductsNotifier extends AsyncNotifier<List<ProductModel>> {
  @override
  Future<List<ProductModel>> build() async {
    try {
      debugPrint('[ProductsNotifier] build: loading products...');
      final result = await ref.watch(productsRepositoryProvider).getAll();
      debugPrint('[ProductsNotifier] build: loaded ${result.length} products.');
      return result;
    } catch (e, st) {
      debugPrint('[ProductsNotifier] build error: $e\n$st');
      rethrow;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> add(ProductModel model) async {
    await ref.read(productsRepositoryProvider).add(model);
    ref.invalidateSelf();
    // Re-fetch the newly added product from DB so it gets the generated ID
    if (model.barcode.isNotEmpty) {
      final newProd = await ref.read(productsRepositoryProvider).findByBarcode(model.barcode);
      if (newProd != null) ref.read(posProductsProvider.notifier).syncProduct(newProd);
    }
  }

  Future<void> updateProduct(ProductModel model) async {
    await ref.read(productsRepositoryProvider).update(model);
    ref.invalidateSelf();
    ref.read(posProductsProvider.notifier).syncProduct(model);
  }

  Future<void> toggle(int id, bool isActive) async {
    await ref.read(productsRepositoryProvider).toggle(id, isActive);
    ref.invalidateSelf();
    if (!isActive) {
      ref.read(posProductsProvider.notifier).removeProduct(id);
    } else {
      final p = await ref.read(productsRepositoryProvider).getProductById(id);
      if (p != null) ref.read(posProductsProvider.notifier).syncProduct(p);
    }
  }

  Future<void> search(String query) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(productsRepositoryProvider);
      if (query.isEmpty) {
        state = AsyncValue.data(await repo.getAll());
      } else {
        state = AsyncValue.data(await repo.search(query));
      }
    } catch (e, st) {
      debugPrint('[ProductsNotifier] search error: $e\n$st');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> filterByCategory(int? categoryId) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(productsRepositoryProvider);
      if (categoryId == null) {
        state = AsyncValue.data(await repo.getAll());
      } else {
        state = AsyncValue.data(await repo.getByCategory(categoryId));
      }
    } catch (e, st) {
      debugPrint('[ProductsNotifier] filterByCategory error: $e\n$st');
      state = AsyncValue.error(e, st);
    }
  }

  Future<ProductModel?> findByBarcode(String barcode) {
    return ref.read(productsRepositoryProvider).findByBarcode(barcode);
  }
}

final productsNotifierProvider =
    AsyncNotifierProvider<ProductsNotifier, List<ProductModel>>(ProductsNotifier.new);
