import '../../../core/theme/app_colors.dart';
import '../../reports/core/models/report_chart_models.dart';
import '../../reports/modules/shared/analytics_formatters.dart';
import '../models/dashboard_filter.dart';
import '../models/financial_dashboard_cash_analytics.dart';

/// Maps certified Phase 5.3.1 analytics models to shared [ReportChartConfig].
///
/// All formatting for chart display lives here -- not in provider or repository.
class FinancialDashboardChartMapper {
  FinancialDashboardChartMapper._();

  static const _kEmptyChartMessage =
      '\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u064a\u0627\u0646\u0627\u062a \u0644\u0644\u0639\u0631\u0636';

  static String _yAxisLabel(double value) =>
      AnalyticsFormatters.currency.format(value);

  static String _formatBucketLabel(String raw, DashboardGranularity granularity) {
    if (granularity == DashboardGranularity.week && raw.startsWith('week:')) {
      final index = int.tryParse(raw.substring(5));
      if (index != null) return '\u0623\u0633\u0628\u0648\u0639 ${index + 1}';
    }

    if (granularity == DashboardGranularity.day && raw.length >= 10) {
      final parts = raw.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}';
      }
    }

    if (granularity == DashboardGranularity.month && raw.length == 7) {
      final parts = raw.split('-');
      if (parts.length == 2) {
        return '${parts[1]}/${parts[0]}';
      }
    }

    return raw;
  }

  /// Cash flow trend -- inflow vs outflow per time bucket.
  ///
  /// Uses [ReportChartType.bar] because the shared line/trend renderer plots
  /// only the primary series; bar supports dual inflow/outflow via
  /// [ReportChartConfig.secondarySeries]. Read-only -- [ReportChartConfig.onPointTap]
  /// is omitted (null).
  static ReportChartConfig toCashFlowTrendChart(
    FinancialDashboardCashFlowTimeSeries timeSeries,
  ) {
    final granularity = timeSeries.granularity;
    final points = timeSeries.buckets
        .map(
          (b) => ReportChartPoint(
            label: _formatBucketLabel(b.label, granularity),
            value: b.inflow,
            secondaryValue: b.outflow,
          ),
        )
        .toList(growable: false);

    return ReportChartConfig(
      title: '\u0627\u062a\u062c\u0627\u0647 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
      type: ReportChartType.bar,
      yAxisFormatter: _yAxisLabel,
      emptyMessage: _kEmptyChartMessage,
      series: [
        ReportChartSeries(
          id: 'inflow',
          label: '\u0627\u0644\u062f\u0627\u062e\u0644',
          color: AppColors.success,
          points: points
              .map((p) => ReportChartPoint(label: p.label, value: p.value))
              .toList(growable: false),
        ),
      ],
      secondarySeries: ReportChartSeries(
        id: 'outflow',
        label: '\u0627\u0644\u062e\u0631\u062c',
        color: AppColors.error,
        points: points
            .map(
              (p) => ReportChartPoint(
                label: p.label,
                value: p.secondaryValue ?? 0,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  /// Cash flow composition -- amount by ledger event type.
  ///
  /// Zero-amount slices are omitted for pie readability only; totals unchanged
  /// at repository level. Read-only -- no [ReportChartConfig.onPointTap].
  static ReportChartConfig toCashFlowCompositionChart(
    FinancialDashboardCashFlowBreakdown breakdown,
  ) {
    final points = breakdown.slices
        .where((s) => s.amount > 0)
        .map(
          (s) => ReportChartPoint(
            label: s.eventType.labelAr,
            value: s.amount,
          ),
        )
        .toList(growable: false);

    return ReportChartConfig(
      title: '\u062a\u0648\u0632\u064a\u0639 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
      type: ReportChartType.pie,
      yAxisFormatter: (v) => AnalyticsFormatters.money(v),
      emptyMessage: _kEmptyChartMessage,
      series: [
        ReportChartSeries(
          id: 'composition',
          label: '\u0627\u0644\u062a\u0648\u0632\u064a\u0639',
          color: AppColors.primary,
          points: points,
        ),
      ],
    );
  }
}