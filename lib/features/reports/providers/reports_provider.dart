import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../customers/providers/customer_accounts_provider.dart';

// --- Repository ---

class ReportsRepository {
  final AppDatabase _db;
  ReportsRepository(this._db);

  // From SalesDao
  Future<Map<String, dynamic>> getDailyTotals(DateTime date) =>
      _db.salesDao.getDailyTotals(date);
  Future<List<Map<String, dynamic>>> getMonthlyTotals(int year) =>
      _db.salesDao.getMonthlyTotals(year);
  Future<List<Map<String, dynamic>>> getTopProducts(DateTime from, DateTime to,
          {int limit = 10}) =>
      _db.salesDao.getTopSellingProducts(from, to, limit: limit);

  // From PurchasesDao
  Future<List<Map<String, dynamic>>> getPurchasesBySupplier(
          DateTime from, DateTime to) =>
      _db.purchasesDao.getPurchasesBySupplier(from, to);

  // From StockDao
  Future<List<Map<String, dynamic>>> getInventoryValueReport() =>
      _db.stockDao.getInventoryValueReport();

  // From CustomersDao
  Future<List<Map<String, dynamic>>> getTopCustomers() =>
      _db.customersDao.getTopCustomersBySpending();
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(AppDatabase.instance);
});

// --- Providers ---

final reportDailySalesProvider =
    FutureProvider.family<Map<String, dynamic>, DateTime>((ref, date) async {
  try {
    debugPrint('[reportDailySalesProvider] loading for date: $date');
    return await ref.watch(reportsRepositoryProvider).getDailyTotals(date);
  } catch (e, st) {
    debugPrint('[reportDailySalesProvider] error: $e\n$st');
    rethrow;
  }
});

final reportTopProductsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange>(
        (ref, range) async {
  try {
    debugPrint(
        '[reportTopProductsProvider] loading range: ${range.start} -> ${range.end}');
    return await ref
        .watch(reportsRepositoryProvider)
        .getTopProducts(range.start, range.end);
  } catch (e, st) {
    debugPrint('[reportTopProductsProvider] error: $e\n$st');
    rethrow;
  }
});

final reportMonthlySalesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, year) async {
  try {
    debugPrint('[reportMonthlySalesProvider] loading year: $year');
    return await ref.watch(reportsRepositoryProvider).getMonthlyTotals(year);
  } catch (e, st) {
    debugPrint('[reportMonthlySalesProvider] error: $e\n$st');
    rethrow;
  }
});

final reportPurchasesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange>(
        (ref, range) async {
  try {
    debugPrint(
        '[reportPurchasesProvider] loading range: ${range.start} -> ${range.end}');
    return await ref
        .watch(reportsRepositoryProvider)
        .getPurchasesBySupplier(range.start, range.end);
  } catch (e, st) {
    debugPrint('[reportPurchasesProvider] error: $e\n$st');
    rethrow;
  }
});

final reportInventoryValueProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    debugPrint('[reportInventoryValueProvider] loading...');
    return await ref.watch(reportsRepositoryProvider).getInventoryValueReport();
  } catch (e, st) {
    debugPrint('[reportInventoryValueProvider] error: $e\n$st');
    rethrow;
  }
});

final reportTopCustomersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    debugPrint('[reportTopCustomersProvider] loading...');
    return await ref.watch(reportsRepositoryProvider).getTopCustomers();
  } catch (e, st) {
    debugPrint('[reportTopCustomersProvider] error: $e\n$st');
    rethrow;
  }
});

final reportTotalOutstandingProvider = FutureProvider<double>((ref) async {
  try {
    debugPrint('[reportTotalOutstandingProvider] loading...');
    return await ref.watch(customerAccountsDaoProvider).getTotalOutstanding();
  } catch (e, st) {
    debugPrint('[reportTotalOutstandingProvider] error: $e\n$st');
    rethrow;
  }
});

final reportTopDebtorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    debugPrint('[reportTopDebtorsProvider] loading...');
    return await ref.watch(customerAccountsDaoProvider).getTopDebtors(limit: 50);
  } catch (e, st) {
    debugPrint('[reportTopDebtorsProvider] error: $e\n$st');
    rethrow;
  }
});
