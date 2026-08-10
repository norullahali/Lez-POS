// lib/features/returns/providers/supplier_returns_list_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/supplier_return_history_models.dart';
import 'supplier_return_draft_provider.dart';
import 'supplier_return_service_provider.dart';

final supplierReturnsSearchProvider = StateProvider<String>((ref) => '');

final supplierReturnsListProvider =
    FutureProvider.autoDispose<List<SupplierReturnListItem>>((ref) async {
  ref.watch(supplierReturnsRefreshProvider);
  final repo = ref.read(supplierReturnReadRepositoryProvider);
  final search = ref.watch(supplierReturnsSearchProvider).trim().toLowerCase();
  final rows = await repo.listSupplierReturns();
  if (search.isEmpty) return rows;
  return rows
      .where(
        (row) =>
            row.displayReturnNumber.toLowerCase().contains(search) ||
            row.displaySupplierName.toLowerCase().contains(search) ||
            row.displayPurchaseInvoice.toLowerCase().contains(search) ||
            row.reason.toLowerCase().contains(search),
      )
      .toList();
});

final supplierReturnDetailProvider = FutureProvider.autoDispose
    .family<SupplierReturnDetail?, int>((ref, returnId) async {
  final repo = ref.read(supplierReturnReadRepositoryProvider);
  return repo.getSupplierReturnDetail(returnId);
});
