// lib/features/categories/providers/categories_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../models/category_model.dart';
import '../repositories/categories_repository.dart';

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(AppDatabase.instance);
});

final categoriesStreamProvider = StreamProvider<List<CategoryModel>>((ref) {
  return ref.watch(categoriesRepositoryProvider).watchAll();
});

final categoriesListProvider = FutureProvider<List<CategoryModel>>((ref) async {
  try {
    return await ref.watch(categoriesRepositoryProvider).getAll();
  } catch (e, st) {
    debugPrint('[categoriesListProvider] error: $e\n$st');
    rethrow;
  }
});

class CategoriesNotifier extends AsyncNotifier<List<CategoryModel>> {
  @override
  Future<List<CategoryModel>> build() async {
    try {
      debugPrint('[CategoriesNotifier] build: loading categories...');
      final result = await ref.watch(categoriesRepositoryProvider).getAll();
      debugPrint('[CategoriesNotifier] build: loaded ${result.length} categories.');
      return result;
    } catch (e, st) {
      debugPrint('[CategoriesNotifier] build error: $e\n$st');
      rethrow;
    }
  }

  Future<void> add(CategoryModel model) async {
    await ref.read(categoriesRepositoryProvider).add(model);
    ref.invalidateSelf();
  }

  Future<void> updateCategory(CategoryModel model) async {
    await ref.read(categoriesRepositoryProvider).update(model);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    await ref.read(categoriesRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }
}

final categoriesNotifierProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<CategoryModel>>(CategoriesNotifier.new);
