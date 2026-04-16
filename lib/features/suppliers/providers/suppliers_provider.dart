// lib/features/suppliers/providers/suppliers_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../models/supplier_model.dart';
import '../repositories/suppliers_repository.dart';

final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  return SuppliersRepository(AppDatabase.instance);
});

final suppliersStreamProvider = StreamProvider<List<SupplierModel>>((ref) {
  return ref.watch(suppliersRepositoryProvider).watchAll();
});

final suppliersListProvider = FutureProvider<List<SupplierModel>>((ref) async {
  try {
    return await ref.watch(suppliersRepositoryProvider).getAll();
  } catch (e, st) {
    debugPrint('[suppliersListProvider] error: $e\n$st');
    rethrow;
  }
});

class SuppliersNotifier extends AsyncNotifier<List<SupplierModel>> {
  @override
  Future<List<SupplierModel>> build() async {
    try {
      debugPrint('[SuppliersNotifier] build: loading suppliers...');
      final result = await ref.watch(suppliersRepositoryProvider).getAll();
      debugPrint('[SuppliersNotifier] build: loaded ${result.length} suppliers.');
      return result;
    } catch (e, st) {
      debugPrint('[SuppliersNotifier] build error: $e\n$st');
      rethrow;
    }
  }

  Future<void> add(SupplierModel model) async {
    await ref.read(suppliersRepositoryProvider).add(model);
    ref.invalidateSelf();
  }

  Future<void> updateSupplier(SupplierModel model) async {
    await ref.read(suppliersRepositoryProvider).update(model);
    ref.invalidateSelf();
  }

  Future<void> delete(int id) async {
    await ref.read(suppliersRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }

  Future<void> search(String query) async {
    state = const AsyncValue.loading();
    try {
      if (query.isEmpty) {
        state = AsyncValue.data(await ref.read(suppliersRepositoryProvider).getAll());
      } else {
        state = AsyncValue.data(await ref.read(suppliersRepositoryProvider).search(query));
      }
    } catch (e, st) {
      debugPrint('[SuppliersNotifier] search error: $e\n$st');
      state = AsyncValue.error(e, st);
    }
  }
}

final suppliersNotifierProvider =
    AsyncNotifierProvider<SuppliersNotifier, List<SupplierModel>>(SuppliersNotifier.new);
