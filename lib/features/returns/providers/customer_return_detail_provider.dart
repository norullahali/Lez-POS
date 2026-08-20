// lib/features/returns/providers/customer_return_detail_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../models/customer_return_history_models.dart';
import '../repositories/customer_return_read_repository.dart';

final customerReturnReadRepositoryProvider =
    Provider<CustomerReturnReadRepository>((ref) {
  return CustomerReturnReadRepository(AppDatabase.instance);
});

final customerReturnDetailProvider = FutureProvider.autoDispose
    .family<CustomerReturnDetail?, int>((ref, returnId) async {
  final repo = ref.read(customerReturnReadRepositoryProvider);
  return repo.getCustomerReturnDetail(returnId);
});
