import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../customers/providers/customer_accounts_provider.dart';
import '../core/models/report_tab_id.dart';
import '../core/services/report_query_cache.dart';

// --- Repository ---

class ReportsRepository {
  final AppDatabase _db;
  ReportsRepository(this._db);

  Future<Map<String, dynamic>> getDailyTotals(DateTime date) =>
      _db.salesDao.getDailyTotals(date);
  Future<List<Map<String, dynamic>>> getMonthlyTotals(int year) =>
      _db.salesDao.getMonthlyTotals(year);
  Future<List<Map<String, dynamic>>> getTopProducts(DateTime from, DateTime to,
          {int limit = 10}) =>
      _db.salesDao.getTopSellingProducts(from, to, limit: limit);

  Future<List<Map<String, dynamic>>> getPurchasesBySupplier(
          DateTime from, DateTime to) =>
      _db.purchasesDao.getPurchasesBySupplier(from, to);

  Future<List<Map<String, dynamic>>> getInventoryValueReport() =>
      _db.stockDao.getInventoryValueReport();

  Future<List<Map<String, dynamic>>> getTopCustomers() =>
      _db.customersDao.getTopCustomersBySpending();
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(AppDatabase.instance);
});

Future<T> _cachedReport<T>(String key, Future<T> Function() fetch) async {
  final hit = ReportQueryCache.get<T>(key);
  if (hit != null) return hit;
  final data = await fetch();
  ReportQueryCache.set(key, data as Object);
  return data;
}

// --- Providers ---

final reportDailySalesProvider =
    FutureProvider.family<Map<String, dynamic>, DateTime>((ref, date) async {
  final key = '${ReportTabId.daily.cachePrefix}${date.toIso8601String().split('T').first}';
  return _cachedReport(key, () => ref.watch(reportsRepositoryProvider).getDailyTotals(date));
});

final reportTopProductsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange>(
        (ref, range) async {
  final key =
      '${ReportTabId.topProducts.cachePrefix}${range.start.toIso8601String()}_${range.end.toIso8601String()}';
  return _cachedReport(
    key,
    () => ref.watch(reportsRepositoryProvider).getTopProducts(range.start, range.end),
  );
});

final reportMonthlySalesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, int>((ref, year) async {
  final key = '${ReportTabId.monthly.cachePrefix}$year';
  return _cachedReport(key, () => ref.watch(reportsRepositoryProvider).getMonthlyTotals(year));
});

final reportPurchasesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, DateTimeRange>(
        (ref, range) async {
  final key =
      '${ReportTabId.purchases.cachePrefix}${range.start.toIso8601String()}_${range.end.toIso8601String()}';
  return _cachedReport(
    key,
    () => ref.watch(reportsRepositoryProvider).getPurchasesBySupplier(range.start, range.end),
  );
});

final reportInventoryValueProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final key = '${ReportTabId.inventory.cachePrefix}all';
  return _cachedReport(key, () => ref.watch(reportsRepositoryProvider).getInventoryValueReport());
});

final reportTopCustomersProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final key = '${ReportTabId.topCustomers.cachePrefix}all';
  return _cachedReport(key, () => ref.watch(reportsRepositoryProvider).getTopCustomers());
});

final reportTotalOutstandingProvider = FutureProvider<double>((ref) async {
  final key = '${ReportTabId.customerDebts.cachePrefix}total';
  return _cachedReport(key, () => ref.watch(customerAccountsDaoProvider).getTotalOutstanding());
});

final reportTopDebtorsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final key = '${ReportTabId.customerDebts.cachePrefix}debtors';
  return _cachedReport(key, () => ref.watch(customerAccountsDaoProvider).getTopDebtors(limit: 50));
});
