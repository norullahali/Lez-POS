// lib/features/customers/providers/customers_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../repositories/customers_repository.dart';

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return CustomersRepository(AppDatabase.instance);
});

final customersStreamProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customersRepositoryProvider).watchAll();
});

class CustomersNotifier extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() async {
    try {
      debugPrint('[CustomersNotifier] build: loading customers...');
      final result = await ref.watch(customersRepositoryProvider).getAll();
      debugPrint('[CustomersNotifier] build: loaded ${result.length} customers.');
      return result;
    } catch (e, st) {
      debugPrint('[CustomersNotifier] build error: $e\n$st');
      rethrow;
    }
  }

  Future<int> save(Customer customer) async {
    try {
      final id = await ref.read(customersRepositoryProvider).save(customer);
      ref.invalidateSelf();
      return id;
    } catch (e, st) {
      debugPrint('[CustomersNotifier] save error: $e\n$st');
      rethrow;
    }
  }

  Future<void> toggleActive(Customer customer, bool isActive) async {
    try {
      await ref.read(customersRepositoryProvider).toggleActive(customer, isActive);
      ref.invalidateSelf();
    } catch (e, st) {
      debugPrint('[CustomersNotifier] toggleActive error: $e\n$st');
      rethrow;
    }
  }
}

final customersNotifierProvider =
    AsyncNotifierProvider<CustomersNotifier, List<Customer>>(CustomersNotifier.new);
