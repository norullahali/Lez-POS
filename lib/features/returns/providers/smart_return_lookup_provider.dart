// lib/features/returns/providers/smart_return_lookup_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../models/smart_return_result.dart';
import '../repositories/smart_return_lookup_repository.dart';

final smartReturnLookupRepositoryProvider =
    Provider<SmartReturnLookupRepository>((ref) {
  return SmartReturnLookupRepository(AppDatabase.instance);
});

final smartReturnLookupProvider = FutureProvider.autoDispose
    .family<List<SmartReturnResult>, String>((ref, query) async {
  if (query.trim().length < 2) return const [];
  return ref.read(smartReturnLookupRepositoryProvider).search(query.trim());
});