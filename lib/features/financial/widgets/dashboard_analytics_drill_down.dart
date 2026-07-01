import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../reports/core/models/report_date_preset.dart';
import '../../reports/core/models/report_filter_model.dart';
import '../models/cash_ledger_event_type.dart';
import '../models/dashboard_filter.dart';
import '../models/financial_dashboard_cash_analytics.dart';
import '../providers/cash_ledger_filter_provider.dart';
import 'dashboard_analytics_chart_selection.dart';

/// Presentation-only bridge from analytics chart selection to Cash Ledger filters.
///
/// **Presentation boundary:** maps indices and bucket labels already resolved by
/// [FinancialDashboardCashAnalytics] — no repository access, no SQL, no aggregation.
///
/// **Navigation boundary:** UI calls [navigateToCashLedger]; this class updates
/// [cashLedgerFilterProvider] at tap time and routes to the certified ledger screen.
/// Dashboard and analytics providers are never invalidated here.
///
/// **Reuse rationale:** [CashLedgerScreen] already owns filter bar, table, and
/// permissions. Aggregate charts lack per-event IDs, so entity drill-down services
/// are not used — filters + [cashLedgerRoute] only.
///
/// **Known limitation (merged buckets):** when the repository merges buckets for
/// chart cap, bucket labels store `chunk.first` only. Trend drill-down therefore
/// opens the first sub-period of a merged bucket, not the full merged span.
class DashboardAnalyticsDrillDown {
  DashboardAnalyticsDrillDown._();

  /// Certified Cash Ledger route — same as [CashLedgerScreen] in `app.dart`.
  static const cashLedgerRoute = '/financial';

  /// Whether [mapSelection] succeeds for the active chart selection.
  ///
  /// Delegates to [mapSelection] intentionally — single source of truth for
  /// gating the feedback drill-down button.
  static bool canNavigate({
    required DashboardFilter dashboardFilter,
    required FinancialDashboardCashAnalytics analytics,
    required DashboardAnalyticsChartSelection selection,
  }) =>
      mapSelection(
            dashboardFilter: dashboardFilter,
            analytics: analytics,
            selection: selection,
          ) !=
          null;

  /// Maps chart selection to Cash Ledger filter fields (presentation only).
  static DashboardAnalyticsCashLedgerMapping? mapSelection({
    required DashboardFilter dashboardFilter,
    required FinancialDashboardCashAnalytics analytics,
    required DashboardAnalyticsChartSelection selection,
  }) {
    return switch (selection) {
      DashboardTrendBucketSelection(:final bucketIndex) => _mapTrendBucket(
          dashboardFilter: dashboardFilter,
          timeSeries: analytics.timeSeries,
          bucketIndex: bucketIndex,
        ),
      DashboardCompositionSliceSelection(:final sliceIndex) =>
        _mapCompositionSlice(
          dashboardFilter: dashboardFilter,
          breakdown: analytics.breakdown,
          sliceIndex: sliceIndex,
        ),
    };
  }

  /// Applies mapped filters and navigates to [cashLedgerRoute].
  ///
  /// Does not touch dashboard or analytics providers.
  static void navigateToCashLedger({
    required BuildContext context,
    required WidgetRef ref,
    required DashboardFilter dashboardFilter,
    required FinancialDashboardCashAnalytics analytics,
    required DashboardAnalyticsChartSelection selection,
  }) {
    final mapping = mapSelection(
      dashboardFilter: dashboardFilter,
      analytics: analytics,
      selection: selection,
    );
    if (mapping == null) return;

    _applyMappingToCashLedgerFilter(ref, mapping);
    context.go(cashLedgerRoute);
  }

  /// Writes presentation-mapped filters via the existing Cash Ledger filter API.
  static void _applyMappingToCashLedgerFilter(
    WidgetRef ref,
    DashboardAnalyticsCashLedgerMapping mapping,
  ) {
    final notifier = ref.read(cashLedgerFilterProvider.notifier);
    notifier.resetFilters();
    notifier.setDateFilter(mapping.dateFilter);
    if (mapping.eventType != null) {
      notifier.setEventType(mapping.eventType);
    }
  }

  /// Trend drill-down: selected bucket → custom date range; event type cleared by reset.
  static DashboardAnalyticsCashLedgerMapping? _mapTrendBucket({
    required DashboardFilter dashboardFilter,
    required FinancialDashboardCashFlowTimeSeries timeSeries,
    required int bucketIndex,
  }) {
    final buckets = timeSeries.buckets;
    if (bucketIndex < 0 || bucketIndex >= buckets.length) return null;

    final bucketRange = _bucketDateRange(
      label: buckets[bucketIndex].label,
      granularity: timeSeries.granularity,
      dashboardRange: dashboardFilter.resolvedRange,
    );
    if (bucketRange == null) return null;

    return DashboardAnalyticsCashLedgerMapping(
      dateFilter: ReportFilterModel(
        preset: ReportDatePreset.custom,
        range: bucketRange,
      ),
    );
  }

  /// Composition drill-down: dashboard period + event type from positive slice index.
  ///
  /// [sliceIndex] matches the pie chart positive-slice order (same as feedback card).
  static DashboardAnalyticsCashLedgerMapping? _mapCompositionSlice({
    required DashboardFilter dashboardFilter,
    required FinancialDashboardCashFlowBreakdown breakdown,
    required int sliceIndex,
  }) {
    final positiveSlices = _positiveSlices(breakdown);
    if (sliceIndex < 0 || sliceIndex >= positiveSlices.length) return null;

    return DashboardAnalyticsCashLedgerMapping(
      dateFilter: dashboardFilter.dateFilter,
      eventType: positiveSlices[sliceIndex].eventType,
    );
  }

  /// Positive slices only — presentation filter aligned with composition pie chart.
  static List<FinancialDashboardBreakdownSlice> _positiveSlices(
    FinancialDashboardCashFlowBreakdown breakdown,
  ) =>
      breakdown.slices.where((s) => s.amount > 0).toList(growable: false);

  /// Translates a trend bucket label into a [DateTimeRange] within the dashboard period.
  ///
  /// Label formats match repository bucket keys: day `YYYY-MM-DD`, week `week:N`,
  /// month `YYYY-MM`. All results are clamped to [dashboardRange] (inclusive end).
  ///
  /// **Merged-bucket caveat:** under chart cap merge, [label] is the first key in
  /// the merged chunk — drill-down resolves that sub-period only (day/week/month).
  static DateTimeRange? _bucketDateRange({
    required String label,
    required DashboardGranularity granularity,
    required DateTimeRange dashboardRange,
  }) {
    final rangeStart = _startOfDay(dashboardRange.start);
    final rangeEnd = _startOfDay(dashboardRange.end);

    switch (granularity) {
      // Single calendar day; rejects labels outside dashboard range.
      case DashboardGranularity.day:
        final parsed = DateTime.tryParse(label);
        if (parsed == null) return null;
        final day = DateTime(parsed.year, parsed.month, parsed.day);
        if (day.isBefore(rangeStart) || day.isAfter(rangeEnd)) return null;
        return DateTimeRange(start: day, end: day);

      // Week index N from dashboard range start: days [N×7 .. N×7+6], clamped.
      case DashboardGranularity.week:
        if (!label.startsWith('week:')) return null;
        final weekIndex = int.tryParse(label.substring(5));
        if (weekIndex == null || weekIndex < 0) return null;
        final weekStart = rangeStart.add(Duration(days: weekIndex * 7));
        if (weekStart.isAfter(rangeEnd)) return null;
        var weekEnd = weekStart.add(const Duration(days: 6));
        if (weekEnd.isAfter(rangeEnd)) weekEnd = rangeEnd;
        return DateTimeRange(start: weekStart, end: weekEnd);

      // Calendar month clamped to dashboard range boundaries.
      case DashboardGranularity.month:
        final parts = label.split('-');
        if (parts.length != 2) return null;
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        if (year == null || month == null || month < 1 || month > 12) return null;
        final monthStart = DateTime(year, month, 1);
        final monthEnd = DateTime(year, month + 1, 0);
        final start = monthStart.isBefore(rangeStart) ? rangeStart : monthStart;
        final end = monthEnd.isAfter(rangeEnd) ? rangeEnd : monthEnd;
        if (start.isAfter(end)) return null;
        return DateTimeRange(start: start, end: end);
    }
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// Cash Ledger filter fields derived from an analytics chart selection.
class DashboardAnalyticsCashLedgerMapping {
  const DashboardAnalyticsCashLedgerMapping({
    required this.dateFilter,
    this.eventType,
  });

  final ReportFilterModel dateFilter;
  final CashLedgerEventType? eventType;
}