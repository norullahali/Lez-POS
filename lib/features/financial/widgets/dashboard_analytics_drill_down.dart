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
import 'dashboard_analytics_trend_bucket_presentation.dart';

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
/// **Trend drill-down (Phase 5.3.3.3):** uses cached
/// [DashboardTrendBucketPresentationMeta] from the UI layer — not label parsing.
/// Empty presentation list fail-closed: trend drill-down is disabled.
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
    required List<DashboardTrendBucketPresentationMeta> trendBucketPresentation,
  }) =>
      mapSelection(
        dashboardFilter: dashboardFilter,
        analytics: analytics,
        selection: selection,
        trendBucketPresentation: trendBucketPresentation,
      ) !=
      null;

  /// Maps chart selection to Cash Ledger filter fields (presentation only).
  static DashboardAnalyticsCashLedgerMapping? mapSelection({
    required DashboardFilter dashboardFilter,
    required FinancialDashboardCashAnalytics analytics,
    required DashboardAnalyticsChartSelection selection,
    required List<DashboardTrendBucketPresentationMeta> trendBucketPresentation,
  }) {
    return switch (selection) {
      DashboardTrendBucketSelection(:final bucketIndex) => _mapTrendBucket(
          bucketIndex: bucketIndex,
          trendBucketPresentation: trendBucketPresentation,
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
    required List<DashboardTrendBucketPresentationMeta> trendBucketPresentation,
  }) {
    final mapping = mapSelection(
      dashboardFilter: dashboardFilter,
      analytics: analytics,
      selection: selection,
      trendBucketPresentation: trendBucketPresentation,
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

  /// Trend drill-down: presentation metadata → custom date range.
  ///
  /// Fail-closed when [trendBucketPresentation] is empty or [bucketIndex] is
  /// out of range — returns null so the feedback button stays hidden.
  static DashboardAnalyticsCashLedgerMapping? _mapTrendBucket({
    required int bucketIndex,
    required List<DashboardTrendBucketPresentationMeta> trendBucketPresentation,
  }) {
    if (bucketIndex < 0 || bucketIndex >= trendBucketPresentation.length) {
      return null;
    }

    final meta = trendBucketPresentation[bucketIndex];
    return DashboardAnalyticsCashLedgerMapping(
      dateFilter: ReportFilterModel(
        preset: ReportDatePreset.custom,
        range: meta.drillDownRange,
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