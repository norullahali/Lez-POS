import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../reports/modules/shared/analytics_formatters.dart';
import '../models/cash_ledger_event.dart';
import '../models/financial_dashboard_cash_analytics.dart';
import '../models/financial_dashboard_cash_flow.dart';
import 'dashboard_analytics_insight.dart';
import 'dashboard_analytics_insights_builder.dart';
import 'dashboard_financial_alert.dart';

/// Deterministic alert generation from certified dashboard data (Phase 5.3.5).
///
/// **Ownership:** invoked by [DashboardAlertsSection] inside `dataBuilder` only.
///
/// **Presentation boundary:** compares pre-aggregated breakdown and time-series
/// values plus optional period KPI data — not accounting rules, not repository
/// aggregation, not persisted, not workflow triggers.
///
/// **Deterministic ordering:** negative cash flow → no income → high spending
/// → expense concentration → cash imbalance. Same inputs always yield the
/// same alert list.
///
/// **Complexity:** O(slices + buckets + insights) per call; bounded by
/// repository chart caps.
class DashboardFinancialAlertsBuilder {
  DashboardFinancialAlertsBuilder._();

  /// Outflow share threshold for a large-expense concentration alert.
  ///
  /// Presentation UX threshold only — stricter than insight concentration at
  /// 60%; not an accounting or approval policy.
  static const expenseConcentrationAlertThreshold = 0.70;

  /// Minimum directional imbalance ratio (vs total flow) for an imbalance alert.
  ///
  /// Presentation UX threshold only — not an accounting or approval policy.
  static const imbalanceRatioThreshold = 0.70;

  /// Minimum buckets before comparing spending halves.
  static const minBucketsForSpendingComparison = 2;

  /// Builds ordered alerts from already-loaded analytics and summary KPIs.
  ///
  /// Returns an empty list when no alert qualifies; the UI shows a read-only
  /// empty-state card — alerts are never fabricated.
  ///
  /// When [insights] is omitted, calls [DashboardAnalyticsInsightsBuilder]
  /// internally (same analytics payload only; no SQL).
  static List<DashboardFinancialAlert> fromContext({
    required FinancialDashboardCashAnalytics analytics,
    FinancialDashboardCashFlow? cashFlow,
    List<DashboardAnalyticsInsight>? insights,
  }) {
    final resolvedInsights =
        insights ?? DashboardAnalyticsInsightsBuilder.fromAnalytics(analytics);

    final alerts = <DashboardFinancialAlert>[];

    _addNegativeCashFlow(analytics, cashFlow, alerts);
    _addNoIncomeDetected(analytics, alerts);
    _addHighSpendingPeriod(analytics, alerts);
    _addLargeExpenseConcentration(analytics, resolvedInsights, alerts);
    _addUnusualCashImbalance(analytics, alerts);

    return alerts;
  }

  static void _addNegativeCashFlow(
    FinancialDashboardCashAnalytics analytics,
    FinancialDashboardCashFlow? cashFlow,
    List<DashboardFinancialAlert> alerts,
  ) {
    // Prefer certified period KPI net; fall back to breakdown-derived net.
    final net = cashFlow?.netCashFlow ?? _netFromBreakdown(analytics);
    if (net >= 0) return;

    alerts.add(
      DashboardFinancialAlert(
        kind: DashboardFinancialAlertKind.negativeCashFlow,
        title: '\u062a\u062f\u0641\u0642 \u0646\u0642\u062f\u064a \u0633\u0627\u0644\u0628 \u0644\u0644\u0641\u062a\u0631\u0629',
        body:
            '\u0635\u0627\u0641\u064a \u0627\u0644\u0646\u0634\u0627\u0637 \u0627\u0644\u0646\u0642\u062f\u064a \u0644\u0644\u0641\u062a\u0631\u0629 \u0633\u0627\u0644\u0628 (${AnalyticsFormatters.money(net)}).',
        icon: Icons.warning_amber_rounded,
        accentColor: AppColors.error,
      ),
    );
  }

  static void _addNoIncomeDetected(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardFinancialAlert> alerts,
  ) {
    final inflow = _totalForDirection(analytics, CashLedgerDirection.inflow);
    if (inflow > 0) return;

    alerts.add(
      const DashboardFinancialAlert(
        kind: DashboardFinancialAlertKind.noIncomeDetected,
        title: '\u0644\u0645 \u064a\u062a\u0645 \u0631\u0635\u062f \u0625\u064a\u0631\u0627\u062f \u0644\u0644\u0641\u062a\u0631\u0629',
        body:
            '\u0644\u0627 \u062a\u0648\u062c\u062f \u062d\u0631\u0643\u0629 \u0625\u064a\u0631\u0627\u062f \u0646\u0642\u062f\u064a \u0645\u0633\u062c\u0644\u0629 \u0641\u064a \u0627\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629.',
        icon: Icons.info_outline_rounded,
        accentColor: AppColors.warning,
      ),
    );
  }

  /// Half-period outflow comparison (distinct from insight net trend).
  ///
  /// Splits [FinancialDashboardCashFlowTimeSeries.buckets] at the midpoint;
  /// emits when second-half outflow exceeds first-half. Equal halves emit none.
  static void _addHighSpendingPeriod(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardFinancialAlert> alerts,
  ) {
    final buckets = analytics.timeSeries.buckets;
    if (buckets.length < minBucketsForSpendingComparison) return;

    final midpoint = buckets.length ~/ 2;
    if (midpoint <= 0 || midpoint >= buckets.length) return;

    final firstOutflow =
        buckets.sublist(0, midpoint).fold<double>(0, (s, b) => s + b.outflow);
    final secondOutflow =
        buckets.sublist(midpoint).fold<double>(0, (s, b) => s + b.outflow);

    if (secondOutflow <= firstOutflow || secondOutflow <= 0) return;

    alerts.add(
      DashboardFinancialAlert(
        kind: DashboardFinancialAlertKind.highSpendingPeriod,
        title: '\u0641\u062a\u0631\u0629 \u0635\u0631\u0641 \u0645\u0631\u062a\u0641\u0639',
        body:
            '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0635\u0631\u0641 \u0641\u064a \u0627\u0644\u0646\u0635\u0641 \u0627\u0644\u062b\u0627\u0646\u064a (${AnalyticsFormatters.money(secondOutflow)}) \u0623\u0639\u0644\u0649 \u0645\u0646 \u0627\u0644\u0646\u0635\u0641 \u0627\u0644\u0623\u0648\u0644 (${AnalyticsFormatters.money(firstOutflow)}).',
        icon: Icons.trending_up_rounded,
        accentColor: AppColors.error,
      ),
    );
  }

  static void _addLargeExpenseConcentration(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardAnalyticsInsight> insights,
    List<DashboardFinancialAlert> alerts,
  ) {
    final outflowSlices = analytics.breakdown.slices
        .where(
          (s) => s.direction == CashLedgerDirection.outflow && s.amount > 0,
        )
        .toList(growable: false);
    if (outflowSlices.isEmpty) return;

    final total = outflowSlices.fold<double>(0, (s, slice) => s + slice.amount);
    if (total <= 0) return;

    final top = _maxByAmount(outflowSlices);
    if (top == null) return;

    final share = top.amount / total;
    // Reuses existing outflow concentration insight (60%) without re-querying.
    // Title substring matches certified insight template for outflow (الصرف).
    final insightFlagsOutflow = insights.any(
      (i) =>
          i.kind == DashboardAnalyticsInsightKind.unusualConcentration &&
          i.title.contains('\u0627\u0644\u0635\u0631\u0641'),
    );
    if (share < expenseConcentrationAlertThreshold && !insightFlagsOutflow) {
      return;
    }

    final percent = (share * 100).round();
    alerts.add(
      DashboardFinancialAlert(
        kind: DashboardFinancialAlertKind.largeExpenseConcentration,
        title: '\u062a\u0631\u0643\u064a\u0632 \u0645\u0631\u062a\u0641\u0639 \u0641\u064a \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a',
        body:
            '${top.eventType.labelAr} \u064a\u0645\u062b\u0644 $percent% \u0645\u0646 \u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0635\u0631\u0641 \u0644\u0644\u0641\u062a\u0631\u0629 (${AnalyticsFormatters.money(top.amount)} \u0645\u0646 ${AnalyticsFormatters.money(total)}).',
        icon: Icons.pie_chart_rounded,
        accentColor: AppColors.warning,
      ),
    );
  }

  static void _addUnusualCashImbalance(
    FinancialDashboardCashAnalytics analytics,
    List<DashboardFinancialAlert> alerts,
  ) {
    final inflow = _totalForDirection(analytics, CashLedgerDirection.inflow);
    final outflow = _totalForDirection(analytics, CashLedgerDirection.outflow);
    final total = inflow + outflow;
    if (total <= 0) return;

    final imbalance = (inflow - outflow).abs() / total;
    if (imbalance < imbalanceRatioThreshold) return;

    final dominantLabel = inflow >= outflow
        ? '\u0627\u0644\u0625\u064a\u0631\u0627\u062f'
        : '\u0627\u0644\u0635\u0631\u0641';
    final percent = (imbalance * 100).round();

    alerts.add(
      DashboardFinancialAlert(
        kind: DashboardFinancialAlertKind.unusualCashImbalance,
        title: '\u0627\u0644\u062a\u0648\u0627\u0632\u0646 \u063a\u064a\u0631 \u0645\u062a\u0648\u0627\u0632\u0646 \u0641\u064a \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
        body:
            '$dominantLabel \u064a\u0647\u064a\u0626 \u0639\u0644\u0649 $percent% \u0645\u0646 \u062d\u0631\u0643\u0629 \u0627\u0644\u0641\u062a\u0631\u0629 (\u0625\u064a\u0631\u0627\u062f ${AnalyticsFormatters.money(inflow)} \u0645\u0642\u0627\u0628\u0644 \u0635\u0631\u0641 ${AnalyticsFormatters.money(outflow)}).',
        icon: Icons.balance_rounded,
        accentColor: AppColors.warning,
      ),
    );
  }

  /// Breakdown-derived period net (inflow − outflow from pre-aggregated slices).
  static double _netFromBreakdown(FinancialDashboardCashAnalytics analytics) =>
      _totalForDirection(analytics, CashLedgerDirection.inflow) -
      _totalForDirection(analytics, CashLedgerDirection.outflow);

  /// Sums pre-aggregated [FinancialDashboardBreakdownSlice] amounts by direction.
  static double _totalForDirection(
    FinancialDashboardCashAnalytics analytics,
    CashLedgerDirection direction,
  ) =>
      analytics.breakdown.slices
          .where((s) => s.direction == direction && s.amount > 0)
          .fold<double>(0, (sum, s) => sum + s.amount);

  /// Largest slice by [FinancialDashboardBreakdownSlice.amount].
  ///
  /// Ties resolve to the first maximal slice in list order — deterministic.
  static FinancialDashboardBreakdownSlice? _maxByAmount(
    List<FinancialDashboardBreakdownSlice> slices,
  ) {
    if (slices.isEmpty) return null;
    return slices.reduce((a, b) => a.amount >= b.amount ? a : b);
  }
}
