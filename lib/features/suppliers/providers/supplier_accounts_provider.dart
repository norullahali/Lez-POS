// lib/features/suppliers/providers/supplier_accounts_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/supplier_accounts_dao.dart';

// Provides the DAO instance
final supplierAccountsDaoProvider = Provider<SupplierAccountsDao>((ref) {
  return AppDatabase.instance.supplierAccountsDao;
});

// Watch current balance for a supplier
final supplierBalanceProvider = StreamProvider.family<double, int>((ref, supplierId) {
  final dao = ref.watch(supplierAccountsDaoProvider);
  return dao.watchBalance(supplierId);
});

// Watch transaction history for a supplier
final supplierHistoryProvider = StreamProvider.family<List<SupplierTransaction>, int>((ref, supplierId) {
  final dao = ref.watch(supplierAccountsDaoProvider);
  return dao.watchHistory(supplierId);
});

// Watch aging buckets for a supplier
final supplierAgingProvider = FutureProvider.family<Map<String, double>, int>((ref, supplierId) async {
  final dao = ref.watch(supplierAccountsDaoProvider);
  return dao.getAgingBuckets(supplierId);
});

// Provider for all creditors (lists top debtors logic but reversed internally for payables)
final topCreditorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dao = ref.watch(supplierAccountsDaoProvider);
  return dao.getTopCreditors();
});

// Provider for total outstanding payable amount
final totalPayableProvider = FutureProvider<double>((ref) async {
  final dao = ref.watch(supplierAccountsDaoProvider);
  return dao.getTotalOutstanding();
});
