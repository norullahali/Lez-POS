// lib/features/customers/providers/customer_accounts_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/daos/customer_accounts_dao.dart';

final customerAccountsDaoProvider = Provider<CustomerAccountsDao>((ref) {
  return AppDatabase.instance.customerAccountsDao;
});

/// Stream of current balance for a customer — live.
final customerBalanceProvider =
    StreamProvider.family<double, int>((ref, customerId) {
  return ref.watch(customerAccountsDaoProvider).watchBalance(customerId);
});

/// Stream of transaction history for a customer.
final customerHistoryProvider =
    StreamProvider.family<List<CustomerTransaction>, int>((ref, customerId) {
  return ref.watch(customerAccountsDaoProvider).watchHistory(customerId);
});

/// Stream of all debtors (balance > 0), ordered desc.
final allDebtorsProvider =
    StreamProvider<List<CustomerAccount>>((ref) {
  return ref.watch(customerAccountsDaoProvider).watchAllDebtors();
});

/// Total outstanding across all customers.
final totalOutstandingProvider = FutureProvider<double>((ref) {
  return ref.watch(customerAccountsDaoProvider).getTotalOutstanding();
});

/// Top debtors list for reports.
final topDebtorsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(customerAccountsDaoProvider).getTopDebtors();
});

/// Aging buckets for one customer — for profile screen + reports.
final customerAgingProvider =
    FutureProvider.family<Map<String, double>, int>((ref, customerId) {
  return ref.watch(customerAccountsDaoProvider).getAgingBuckets(customerId);
});
