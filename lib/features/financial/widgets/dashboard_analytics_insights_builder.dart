import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../reports/modules/shared/analytics_formatters.dart';
import '../models/cash_ledger_event.dart';
import '../models/financial_dashboard_cash_analytics.dart';
import 'dashboard_analytics_insight.dart';

/// Deterministic insight generation from already-loaded analytics (Phase 5.3.4).
///
/// **Ownership:** invoked by [DashboardInsightsSection] inside `dataBuilder` only.
///
/// **Presentation boundary:** ranks and compares certified breakdown/time-series
/// values — not accounting rules, not repository aggregation, not persisted.
///
/// **Deterministic ordering:** income → expense → trend → concentration (inflow
/// then outflow). Same analytics payload always yields the same insight list.
///
/// **Complexity:** O(slices + buckets) per call; bounded by repository chart caps.
class DashboardAnalyticsInsightsBuilder {
  DashboardAnalyticsInsightsBuilder._();

  /// Minimum share of a directional flow for a concentration observation.
  ///
  /// Presentation UX threshold only — not an accounting or approval policy.
  static const concentrationThreshold = 0.60;

  /// Minimum buckets required before emitting a trend observation.
  static const minBucketsForTrend = 2;

  /// Builds ordered insights from [FinancialDashboardCashAnalytics].
  ///
  /// Returns an empty list when no observation qualifies; the UI shows a
  /// read-only empty-state card — insights are never fabricated.
  static List<DashboardAnalyticsInsight> fromAnalytics(
    FinancialDashboardCashAnalytics analytics,
  ) {
    final insights = <DashboardAnalyticsInsight>[];

    _addStrongestIncomeSource(analytics, insights);
    _addLargestExpenseCategory(analytics, insights);
    _addCashFlowTrend(analytics, insights);
    _addConcentrationInsights(analytics, insights);

    return insights;
  }

  static void _addStrongestIncomeSource(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardAnalyticsInsight> insights,
  ) {
    final inflowSlices = analytics.breakdown.slices
        .where(
          (s) => s.direction == CashLedgerDirection.inflow && s.amount > 0,
        )
        .toList(growable: false);
    if (inflowSlices.isEmpty) return;

    final top = _maxByAmount(inflowSlices);
    if (top == null) return;

    insights.add(
      DashboardAnalyticsInsight(
        kind: DashboardAnalyticsInsightKind.strongestIncomeSource,
        title: '\u0623\u0642\u0648\u0649 \u0645\u0635\u062f\u0631 \u062f\u062e\u0644',
        body:
            '${top.eventType.labelAr} \u2014 ${AnalyticsFormatters.money(top.amount)}',
        icon: Icons.arrow_upward_rounded,
        accentColor: AppColors.success,
      ),
    );
  }

  static void _addLargestExpenseCategory(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardAnalyticsInsight> insights,
  ) {
    final outflowSlices = analytics.breakdown.slices
        .where(
          (s) => s.direction == CashLedgerDirection.outflow && s.amount > 0,
        )
        .toList(growable: false);
    if (outflowSlices.isEmpty) return;

    final top = _maxByAmount(outflowSlices);
    if (top == null) return;

    insights.add(
      DashboardAnalyticsInsight(
        kind: DashboardAnalyticsInsightKind.largestExpenseCategory,
        title: '\u0623\u0643\u0628\u0631 \u0628\u0646\u062f \u0635\u0631\u0641',
        body:
            '${top.eventType.labelAr} \u2014 ${AnalyticsFormatters.money(top.amount)}',
        icon: Icons.arrow_downward_rounded,
        accentColor: AppColors.error,
      ),
    );
  }

  /// Half-period net comparison using pre-aggregated bucket values only.
  ///
  /// Splits [FinancialDashboardCashFlowTimeSeries.buckets] at the midpoint;
  /// emits at most one trend insight. Equal nets emit none.
  static void _addCashFlowTrend(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardAnalyticsInsight> insights,
  ) {
    final buckets = analytics.timeSeries.buckets;
    if (buckets.length < minBucketsForTrend) return;

    final midpoint = buckets.length ~/ 2;
    if (midpoint <= 0 || midpoint >= buckets.length) return;

    final firstHalf = buckets.sublist(0, midpoint);
    final secondHalf = buckets.sublist(midpoint);

    final firstNet = _totalNet(firstHalf);
    final secondNet = _totalNet(secondHalf);

    if (firstNet == 0 && secondNet == 0) return;

    if (secondNet > firstNet) {
      insights.add(
        DashboardAnalyticsInsight(
          kind: DashboardAnalyticsInsightKind.positiveCashFlowTrend,
          title: '\u0627\u062a\u062c\u0627\u0647 \u062a\u062f\u0641\u0642 \u0646\u0642\u062f\u064a \u0625\u064a\u062c\u0627\u0628\u064a',
          body:
              '\u0635\u0627\u0641\u064a \u0627\u0644\u0646\u0634\u0627\u0637 \u0641\u064a \u0627\u0644\u0646\u0635\u0641 \u0627\u0644\u062b\u0627\u0646\u064a \u0645\u0646 \u0627\u0644\u0641\u062a\u0631\u0629 (${AnalyticsFormatters.money(secondNet)}) \u0623\u0639\u0644\u0649 \u0645\u0646 \u0627\u0644\u0646\u0635\u0641 \u0627\u0644\u0623\u0648\u0644 (${AnalyticsFormatters.money(firstNet)}).',
          icon: Icons.trending_up_rounded,
          accentColor: AppColors.success,
        ),
      );
      return;
    }

    if (secondNet < firstNet) {
      insights.add(
        DashboardAnalyticsInsight(
          kind: DashboardAnalyticsInsightKind.negativeCashFlowTrend,
          title: '\u0627\u062a\u062c\u0627\u0647 \u062a\u062f\u0641\u0642 \u0646\u0642\u062f\u064a \u0633\u0644\u0628\u064a',
          body:
              '\u0635\u0627\u0641\u064a \u0627\u0644\u0646\u0634\u0627\u0637 \u0641\u064a \u0627\u0644\u0646\u0635\u0641 \u0627\u0644\u062b\u0627\u0646\u064a \u0645\u0646 \u0627\u0644\u0641\u062a\u0631\u0629 (${AnalyticsFormatters.money(secondNet)}) \u0623\u0642\u0644 \u0645\u0646 \u0627\u0644\u0646\u0635\u0641 \u0627\u0644\u0623\u0648\u0644 (${AnalyticsFormatters.money(firstNet)}).',
          icon: Icons.trending_down_rounded,
          accentColor: AppColors.error,
        ),
      );
    }
  }

  static void _addConcentrationInsights(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardAnalyticsInsight> insights,
  ) {
    _addConcentrationForDirection(
      analytics,
      insights,
      direction: CashLedgerDirection.inflow,
      flowLabel: '\u0627\u0644\u0625\u064a\u0631\u0627\u062f',
    );
    _addConcentrationForDirection(
      analytics,
      insights,
      direction: CashLedgerDirection.outflow,
      flowLabel: '\u0627\u0644\u0635\u0631\u0641',
    );
  }

  static void _addConcentrationForDirection(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardAnalyticsInsight> insights, {
    required CashLedgerDirection direction,
    required String flowLabel,
  }) {
    final slices = analytics.breakdown.slices
        .where((s) => s.direction == direction && s.amount > 0)
        .toList(growable: false);
    if (slices.isEmpty) return;

    final total = slices.fold<double>(0, (sum, s) => sum + s.amount);
    if (total <= 0) return;

    final top = _maxByAmount(slices);
    if (top == null) return;

    final share = top.amount / total;
    if (share < concentrationThreshold) return;

    final percent = (share * 100).round();
    insights.add(
      DashboardAnalyticsInsight(
        kind: DashboardAnalyticsInsightKind.unusualConcentration,
        title: '\u062a\u0631\u0643\u064a\u0632 \u063a\u064a\u0631 \u0645\u0639\u062a\u0627\u062f \u0641\u064a $flowLabel',
        body:
            '${top.eventType.labelAr} \u064a\u0645\u062b\u0644 $percent% \u0645\u0646 \u0625\u062c\u0645\u0627\u0644\u064a $flowLabel \u0644\u0644\u0641\u062a\u0631\u0629 (${AnalyticsFormatters.money(top.amount)} \u0645\u0646 ${AnalyticsFormatters.money(total)}).',
        icon: Icons.pie_chart_rounded,
        accentColor: AppColors.warning,
      ),
    );
  }

  /// Largest slice by [FinancialDashboardBreakdownSlice.amount].
  ///
  /// Ties resolve to the first maximal slice in list order (deterministic).
  static FinancialDashboardBreakdownSlice? _maxByAmount(
    List<FinancialDashboardBreakdownSlice> slices,
  ) {
    if (slices.isEmpty) return null;
    return slices.reduce(
      (a, b) => a.amount >= b.amount ? a : b,
    );
  }

  /// Sums bucket nets from already-certified inflow/outflow totals.
  static double _totalNet(List<FinancialDashboardTimeSeriesBucket> buckets) =>
      buckets.fold<double>(0, (sum, b) => sum + (b.inflow - b.outflow));
}
