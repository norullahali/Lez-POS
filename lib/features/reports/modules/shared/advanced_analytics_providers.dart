import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../core/filters/report_filter_provider.dart';
import '../../core/models/report_tab_id.dart';
import '../../core/services/report_query_cache.dart';
import '../../repositories/advanced_analytics_repository.dart';
import 'advanced_analytics_models.dart';
import 'analytics_filter_utils.dart';

final advancedAnalyticsRepositoryProvider = Provider<AdvancedAnalyticsRepository>((ref) {
  return AdvancedAnalyticsRepository(AppDatabase.instance);
});

Future<T> _cachedAnalytics<T>(
  String key,
  Future<T> Function() fetch,
) async {
  final hit = ReportQueryCache.get<T>(key);
  if (hit != null) return hit;
  final data = await fetch();
  ReportQueryCache.set(key, data as Object);
  return data;
}

String _rangeKey(DateTime from, DateTime to) =>
    '${from.toIso8601String().split('T').first}_${to.toIso8601String().split('T').first}';

AnalyticsDateRange resolveAnalyticsRange(Ref ref, ReportTabId tab) {
  final filter = ref.watch(reportSessionProvider.select((s) => s.filterFor(tab)));
  final range = filter.resolveRange();
  return AnalyticsDateRange(from: range.start, to: range.end);
}

/// Session-synced comparative date ranges for period-over-period analytics.
final comparativeRangesProvider = Provider<ComparativeDateRanges>((ref) {
  final filter = ref.watch(reportSessionProvider.select((s) => s.filterFor(ReportTabId.comparativeAnalytics)));
  final currentRange = filter.resolveRange();
  final previous = previousRangeFor(filter);
  return ComparativeDateRanges(
    current: AnalyticsDateRange(from: currentRange.start, to: currentRange.end),
    previous: AnalyticsDateRange(from: previous.from, to: previous.to),
  );
});

final profitAnalysisProvider = FutureProvider.autoDispose<ProfitAnalysisData>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.profitAnalysis);
  final key = '${ReportTabId.profitAnalysis.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getProfitAnalysis(range.from, range.to));
});

final cashFlowProvider = FutureProvider.autoDispose<CashFlowData>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.cashFlow);
  final key = '${ReportTabId.cashFlow.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getCashFlow(range.from, range.to));
});

final returnImpactProvider = FutureProvider.autoDispose<ReturnImpactData>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.returnImpact);
  final key = '${ReportTabId.returnImpact.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getReturnImpact(range.from, range.to));
});

final inventoryMovementProvider = FutureProvider.autoDispose<InventoryMovementData>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.inventoryMovement);
  final key = '${ReportTabId.inventoryMovement.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getInventoryMovement(range.from, range.to));
});

final taxReportProvider = FutureProvider.autoDispose<TaxReportData>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.taxReports);
  final key = '${ReportTabId.taxReports.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getTaxReport(range.from, range.to));
});

final employeePerformanceProvider = FutureProvider.autoDispose<List<EmployeePerformanceRow>>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.employeePerformance);
  final key = '${ReportTabId.employeePerformance.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getEmployeePerformance(range.from, range.to));
});

final hourlySalesProvider = FutureProvider.autoDispose<List<HourlySalesPoint>>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.hourlyHeatmap);
  final key = '${ReportTabId.hourlyHeatmap.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getHourlySales(range.from, range.to));
});

final categoryPerformanceProvider = FutureProvider.autoDispose<List<CategoryPerformanceRow>>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.categoryPerformance);
  final key = '${ReportTabId.categoryPerformance.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getCategoryPerformance(range.from, range.to));
});

final productVelocityProvider = FutureProvider.autoDispose<ProductVelocityData>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.productVelocity);
  final key = '${ReportTabId.productVelocity.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getProductVelocity(range.from, range.to));
});

final executiveDashboardProvider = FutureProvider.autoDispose<ExecutiveDashboardData>((ref) async {
  final range = resolveAnalyticsRange(ref, ReportTabId.executiveDashboard);
  final key = '${ReportTabId.executiveDashboard.cachePrefix}${_rangeKey(range.from, range.to)}';
  return _cachedAnalytics(key, () => ref.read(advancedAnalyticsRepositoryProvider).getExecutiveDashboard(range.from, range.to));
});

final executiveComparisonProvider = FutureProvider.autoDispose<ComparativeAnalyticsData>((ref) async {
  final filter = ref.watch(reportSessionProvider.select((s) => s.filterFor(ReportTabId.executiveDashboard)));
  final currentRange = filter.resolveRange();
  final previous = previousRangeFor(filter);
  final key =
      '${ReportTabId.executiveDashboard.cachePrefix}cmp_${_rangeKey(currentRange.start, currentRange.end)}_${_rangeKey(previous.from, previous.to)}';
  return _cachedAnalytics(
    key,
    () => ref.read(advancedAnalyticsRepositoryProvider).getComparativeAnalytics(
          currentRange.start,
          currentRange.end,
          previous.from,
          previous.to,
        ),
  );
});

final comparativeAnalyticsProvider = FutureProvider.autoDispose<ComparativeAnalyticsData>((ref) async {
  final ranges = ref.watch(comparativeRangesProvider);
  final key =
      '${ReportTabId.comparativeAnalytics.cachePrefix}${_rangeKey(ranges.current.from, ranges.current.to)}_${_rangeKey(ranges.previous.from, ranges.previous.to)}';
  return _cachedAnalytics(
    key,
    () => ref.read(advancedAnalyticsRepositoryProvider).getComparativeAnalytics(
          ranges.current.from,
          ranges.current.to,
          ranges.previous.from,
          ranges.previous.to,
        ),
  );
});