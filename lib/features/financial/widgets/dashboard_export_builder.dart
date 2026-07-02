import 'package:intl/intl.dart';

import '../../reports/modules/shared/analytics_formatters.dart';
import '../models/cash_ledger_event.dart';
import '../models/dashboard_export.dart';
import '../models/dashboard_filter.dart';
import '../models/dashboard_personalization.dart';
import '../models/financial_dashboard_cash_analytics.dart';
import '../models/financial_dashboard_cash_flow.dart';
import '../models/financial_dashboard_current_state.dart';
import 'dashboard_analytics_insights_builder.dart';
import 'dashboard_financial_alerts_builder.dart';
import 'financial_dashboard_chart_mapper.dart';

/// Converts already-loaded dashboard presentation into export structures (Phase 5.3.7).
///
/// **Ownership:** invoked from [FinancialDashboardScreen._prepareExportDocument]
/// on export menu open only.
///
/// **Presentation boundary:** reads optional in-memory snapshots passed by the
/// screen — never repositories, never providers, never SQL, never invalidates
/// analytics. Reuses certified insight and alert builders on supplied analytics.
///
/// **Deterministic ordering:** sections always appended in certified dashboard
/// sequence: cash flow → analytics → insights → alerts → supplementary KPI →
/// recent activity (optional sections skipped when hidden).
///
/// **Complexity:** O(sections + buckets + slices + activity rows) per build;
/// bounded by repository chart caps on the supplied analytics snapshot.
class DashboardExportBuilder {
  DashboardExportBuilder._();

  static const dashboardTitle =
      '\u0644\u0648\u062d\u0629 \u0627\u0644\u0645\u0624\u0634\u0631\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629';

  static const dashboardSubtitle =
      '\u0645\u0644\u062e\u0635 \u0645\u0627\u0644\u064a \u0644\u062d\u0627\u0644\u0629 \u0627\u0644\u0646\u0634\u0627\u0637 \u0627\u0644\u062a\u062c\u0627\u0631\u064a';

  static const _kTrendChartTitle =
      '\u0627\u062a\u062c\u0627\u0647 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a';

  static const _kCompositionChartTitle =
      '\u062a\u0648\u0632\u064a\u0639 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a';

  static const _kActivityTimestampFormat = 'yyyy/MM/dd HH:mm';

  /// Builds an export document from in-memory dashboard snapshots.
  ///
  /// Does not mutate [DashboardExportBuildInput] or any snapshot models.
  static DashboardExportDocument build(DashboardExportBuildInput input) {
    final sections = <DashboardExportSection>[];

    _addCashFlowSection(sections, input);
    _addAnalyticsSection(sections, input);
    _addInsightsSection(sections, input);
    _addAlertsSection(sections, input);
    _addSupplementaryKpiSection(sections, input);
    _addRecentActivitySection(sections, input);

    return DashboardExportDocument(
      title: dashboardTitle,
      subtitle: dashboardSubtitle,
      filterSummary: input.filter.dateFilter.summaryAr(),
      generatedAt: input.generatedAt ?? DateTime.now(),
      sections: sections,
    );
  }

  /// Always included — core dashboard section (collapsible on screen only).
  static void _addCashFlowSection(
    List<DashboardExportSection> sections,
    DashboardExportBuildInput input,
  ) {
    final personalization = input.personalization;
    final cashFlow = input.cashFlow;
    sections.add(
      DashboardExportSection(
        kind: DashboardExportSectionKind.cashFlow,
        title: DashboardSectionId.cashFlow.labelAr,
        visible: true,
        collapsed: personalization.isCollapsed(DashboardSectionId.cashFlow),
        kpis: cashFlow == null ? const [] : _cashFlowKpis(cashFlow),
      ),
    );
  }

  static List<DashboardExportKpi> _cashFlowKpis(
    FinancialDashboardCashFlow cashFlow,
  ) {
    return [
      DashboardExportKpi(
        title: '\u0627\u0644\u0631\u0635\u064a\u062f \u0627\u0644\u0646\u0642\u062f\u064a',
        subtitle:
            '\u0644\u0627 \u064a\u062a\u0623\u062b\u0631 \u0628\u0627\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629',
        value: AnalyticsFormatters.money(cashFlow.cashBalance),
      ),
      DashboardExportKpi(
        title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u062f\u0627\u062e\u0644',
        value: AnalyticsFormatters.money(cashFlow.totalInflow),
      ),
      DashboardExportKpi(
        title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u062e\u0631\u062c',
        value: AnalyticsFormatters.money(cashFlow.totalOutflow),
      ),
      DashboardExportKpi(
        title: '\u0635\u0627\u0641\u064a \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
        value: AnalyticsFormatters.money(cashFlow.netCashFlow),
      ),
    ];
  }

  /// Included when [DashboardPersonalization.showAnalyticsCharts] is true.
  static void _addAnalyticsSection(
    List<DashboardExportSection> sections,
    DashboardExportBuildInput input,
  ) {
    if (!input.personalization.showAnalyticsCharts) return;

    final analytics = input.analytics;
    final charts = analytics == null
        ? const <DashboardExportChart>[]
        : _analyticsCharts(analytics);

    sections.add(
      DashboardExportSection(
        kind: DashboardExportSectionKind.analytics,
        title: DashboardSectionId.analytics.labelAr,
        visible: true,
        collapsed: input.personalization.isCollapsed(DashboardSectionId.analytics),
        charts: charts,
      ),
    );
  }

  static List<DashboardExportChart> _analyticsCharts(
    FinancialDashboardCashAnalytics analytics,
  ) {
    final timeSeries = analytics.timeSeries;
    final rawLabels = timeSeries.buckets.map((b) => b.label);
    final bucketCount = timeSeries.buckets.length;

    final trendRows = timeSeries.buckets
        .map(
          (bucket) => DashboardExportChartRow(
            label: FinancialDashboardChartMapper.formatBucketLabelForDisplay(
              bucket.label,
              timeSeries.granularity,
              bucketCount: bucketCount,
              allRawLabels: rawLabels,
            ),
            primaryValue: AnalyticsFormatters.money(bucket.inflow),
            secondaryValue: AnalyticsFormatters.money(bucket.outflow),
          ),
        )
        .toList(growable: false);

    final compositionRows = analytics.breakdown.slices
        .where((slice) => slice.amount > 0)
        .map(
          (slice) => DashboardExportChartRow(
            label: slice.eventType.labelAr,
            primaryValue: AnalyticsFormatters.money(slice.amount),
          ),
        )
        .toList(growable: false);

    return [
      DashboardExportChart(
        title: _kTrendChartTitle,
        kind: DashboardExportChartKind.trend,
        rows: trendRows,
      ),
      DashboardExportChart(
        title: _kCompositionChartTitle,
        kind: DashboardExportChartKind.composition,
        rows: compositionRows,
      ),
    ];
  }

  /// Included when [DashboardPersonalization.showInsights] is true.
  static void _addInsightsSection(
    List<DashboardExportSection> sections,
    DashboardExportBuildInput input,
  ) {
    if (!input.personalization.showInsights) return;

    final analytics = input.analytics;
    final insights = analytics == null
        ? const <DashboardExportTextItem>[]
        : _insightItemsFromAnalytics(analytics);

    sections.add(
      DashboardExportSection(
        kind: DashboardExportSectionKind.insights,
        title: DashboardSectionId.insights.labelAr,
        visible: true,
        collapsed: input.personalization.isCollapsed(DashboardSectionId.insights),
        insights: insights,
      ),
    );
  }

  /// Included when [DashboardPersonalization.showAlerts] is true.
  static void _addAlertsSection(
    List<DashboardExportSection> sections,
    DashboardExportBuildInput input,
  ) {
    if (!input.personalization.showAlerts) return;

    final analytics = input.analytics;
    if (analytics == null) {
      sections.add(
        DashboardExportSection(
          kind: DashboardExportSectionKind.alerts,
          title: DashboardSectionId.alerts.labelAr,
          visible: true,
          collapsed: input.personalization.isCollapsed(DashboardSectionId.alerts),
        ),
      );
      return;
    }

    final insightModels =
        DashboardAnalyticsInsightsBuilder.fromAnalytics(analytics);
    final alerts = DashboardFinancialAlertsBuilder.fromContext(
      analytics: analytics,
      cashFlow: input.cashFlow,
      insights: insightModels,
    );

    sections.add(
      DashboardExportSection(
        kind: DashboardExportSectionKind.alerts,
        title: DashboardSectionId.alerts.labelAr,
        visible: true,
        collapsed: input.personalization.isCollapsed(DashboardSectionId.alerts),
        alerts: alerts
            .map(
              (alert) => DashboardExportTextItem(
                title: alert.title,
                body: alert.body,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  /// Always included — core dashboard section (collapsible on screen only).
  static void _addSupplementaryKpiSection(
    List<DashboardExportSection> sections,
    DashboardExportBuildInput input,
  ) {
    final state = input.currentState;
    sections.add(
      DashboardExportSection(
        kind: DashboardExportSectionKind.supplementaryKpi,
        title: DashboardSectionId.supplementaryKpi.labelAr,
        visible: true,
        collapsed:
            input.personalization.isCollapsed(DashboardSectionId.supplementaryKpi),
        kpis: state == null ? const [] : _supplementaryKpis(state),
      ),
    );
  }

  static List<DashboardExportKpi> _supplementaryKpis(
    FinancialDashboardCurrentState state,
  ) {
    return [
      DashboardExportKpi(
        title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0641\u062a\u0631\u0629',
        value: AnalyticsFormatters.money(state.totalSales),
      ),
      DashboardExportKpi(
        title: '\u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0628\u0637\u0627\u0642\u0627\u062a',
        value: AnalyticsFormatters.money(state.cardSales),
      ),
      DashboardExportKpi(
        title: '\u062f\u064a\u0648\u0646 \u0627\u0644\u0639\u0645\u0644\u0627\u0621',
        subtitle: '\u0627\u0644\u062d\u0627\u0644\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629',
        value: AnalyticsFormatters.money(state.customerDebt),
      ),
      DashboardExportKpi(
        title: '\u062f\u064a\u0648\u0646 \u0627\u0644\u0645\u0648\u0631\u062f\u064a\u0646',
        subtitle: '\u0627\u0644\u062d\u0627\u0644\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629',
        value: AnalyticsFormatters.money(state.supplierDebt),
      ),
      DashboardExportKpi(
        title: '\u0641\u0631\u0642 \u0627\u0644\u062c\u0644\u0633\u0627\u062a',
        value: AnalyticsFormatters.money(state.sessionDifference),
      ),
    ];
  }

  /// Included when [DashboardPersonalization.showRecentActivity] is true.
  static void _addRecentActivitySection(
    List<DashboardExportSection> sections,
    DashboardExportBuildInput input,
  ) {
    if (!input.personalization.showRecentActivity) return;

    final activity = input.recentActivity;
    final dateFormat = DateFormat(_kActivityTimestampFormat);

    sections.add(
      DashboardExportSection(
        kind: DashboardExportSectionKind.recentActivity,
        title: DashboardSectionId.recentActivity.labelAr,
        visible: true,
        collapsed:
            input.personalization.isCollapsed(DashboardSectionId.recentActivity),
        activityRows: activity == null
            ? const []
            : activity
                .map((event) => _activityRow(event, dateFormat))
                .toList(growable: false),
      ),
    );
  }

  /// Maps certified insight DTOs to export text items (presentation only).
  static List<DashboardExportTextItem> _insightItemsFromAnalytics(
    FinancialDashboardCashAnalytics analytics,
  ) =>
      DashboardAnalyticsInsightsBuilder.fromAnalytics(analytics)
          .map(
            (insight) => DashboardExportTextItem(
              title: insight.title,
              body: insight.body,
            ),
          )
          .toList(growable: false);

  static DashboardExportActivityRow _activityRow(
    CashLedgerEvent event,
    DateFormat dateFormat,
  ) {
    final amountPrefix = event.isInflow ? '+' : '-';
    return DashboardExportActivityRow(
      timestampLabel: dateFormat.format(event.timestamp),
      typeLabel: event.eventType.labelAr,
      amountLabel: '$amountPrefix${AnalyticsFormatters.money(event.amount)}',
      description: event.description,
    );
  }
}

/// In-memory snapshots passed from the dashboard screen (Phase 5.3.7).
///
/// **Ownership:** assembled in [FinancialDashboardScreen._prepareExportDocument].
///
/// **Snapshot policy:** each nullable field is the current `valueOrNull` of a
/// certified dashboard provider — null when async data is loading or errored.
///
/// Populated via `ref.read(...).valueOrNull` — no provider invalidation.
class DashboardExportBuildInput {
  const DashboardExportBuildInput({
    required this.filter,
    required this.personalization,
    this.cashFlow,
    this.analytics,
    this.currentState,
    this.recentActivity,
    this.generatedAt,
  });

  /// Active dashboard filter (filter summary + analytics range context).
  final DashboardFilter filter;

  /// Ephemeral screen-local personalization (Phase 5.3.6).
  final DashboardPersonalization personalization;

  /// Loaded period cash-flow KPIs, if available.
  final FinancialDashboardCashFlow? cashFlow;

  /// Loaded analytics payload (charts + insight/alert source), if available.
  final FinancialDashboardCashAnalytics? analytics;

  /// Loaded supplementary / debt KPIs, if available.
  final FinancialDashboardCurrentState? currentState;

  /// Loaded recent ledger events (page size 10), if available.
  final List<CashLedgerEvent>? recentActivity;

  /// Optional override for export timestamp; defaults to `DateTime.now()` in builder.
  final DateTime? generatedAt;
}