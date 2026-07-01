import '../../../core/theme/app_colors.dart';
import '../../reports/core/models/report_chart_models.dart';
import '../../reports/modules/shared/analytics_formatters.dart';
import '../models/dashboard_filter.dart';
import '../models/financial_dashboard_cash_analytics.dart';

/// Maps certified Phase 5.3.1 analytics models to shared [ReportChartConfig].
///
/// All chart display formatting lives here -- not in provider or repository.
/// Phase 5.3.2.2 refined labels, legends, and empty states; Phase 5.3.3.1
/// adds optional read-only interactivity passthrough ([onPointTap],
/// [selectedPointIndex]). Financial values are passed through unchanged.
class FinancialDashboardChartMapper {
  FinancialDashboardChartMapper._();

  static const _kTrendEmptyMessage =
      '\u0644\u0627 \u062a\u0648\u062c\u062f \u062d\u0631\u0643\u0629 \u0646\u0642\u062f\u064a\u0629 \u0641\u064a \u0627\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629';
  static const _kCompositionEmptyMessage =
      '\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u0646\u0648\u062f \u0644\u062a\u0648\u0632\u064a\u0639 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a \u0641\u064a \u0627\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629';

  static const _kDenseDayLabelThreshold = 14;
  static const _kTrendLegendInflow = '\u0625\u064a\u0631\u0627\u062f \u0646\u0642\u062f\u064a';
  static const _kTrendLegendOutflow = '\u0635\u0631\u0641 \u0646\u0642\u062f\u064a';

  static String _yAxisLabel(double value) =>
      AnalyticsFormatters.currency.format(value);

  static String _tooltipMoney(double value) => AnalyticsFormatters.money(value);

  /// Public wrapper for selection feedback labels (presentation only).
  static String formatBucketLabelForDisplay(
    String raw,
    DashboardGranularity granularity, {
    required int bucketCount,
    required Iterable<String> allRawLabels,
  }) =>
      _formatBucketLabel(
        raw,
        granularity,
        bucketCount: bucketCount,
        allRawLabels: allRawLabels,
      );

  static String _formatBucketLabel(
    String raw,
    DashboardGranularity granularity, {
    required int bucketCount,
    required Iterable<String> allRawLabels,
  }) {
    if (granularity == DashboardGranularity.week && raw.startsWith('week:')) {
      final index = int.tryParse(raw.substring(5));
      if (index != null) return '\u0623\u0633\u0628\u0648\u0639 ${index + 1}';
    }

    if (granularity == DashboardGranularity.day && raw.length >= 10) {
      final parts = raw.split('-');
      if (parts.length == 3) {
        if (bucketCount > _kDenseDayLabelThreshold) {
          final months = allRawLabels
              .where((l) => l.length >= 7)
              .map((l) => l.substring(0, 7))
              .toSet();
          if (months.length <= 1) {
            return int.tryParse(parts[2])?.toString() ?? parts[2];
          }
        }
        return '${parts[2]}/${parts[1]}';
      }
    }

    if (granularity == DashboardGranularity.month && raw.length == 7) {
      final parts = raw.split('-');
      if (parts.length == 2 && parts[0].length == 4) {
        return '${parts[1]}/${parts[0].substring(2)}';
      }
    }

    return raw;
  }

  /// Applies presentation-only interactivity to an existing chart config.
  ///
  /// Does not remap points or alter values -- only attaches [onPointTap] and
  /// [selectedPointIndex] for [ReportChartWidget] highlight / tap handling.
  /// Call after caching base configs from [toCashFlowTrendChart] /
  /// [toCashFlowCompositionChart]; reuse on selection-only rebuilds.
  static ReportChartConfig withInteractivity(
    ReportChartConfig base, {
    void Function(ReportChartPoint point, String seriesId)? onPointTap,
    int? selectedPointIndex,
  }) =>
      ReportChartConfig(
        title: base.title,
        type: base.type,
        series: base.series,
        secondarySeries: base.secondarySeries,
        yAxisFormatter: base.yAxisFormatter,
        emptyMessage: base.emptyMessage,
        animationDuration: base.animationDuration,
        onPointTap: onPointTap,
        selectedPointIndex: selectedPointIndex,
      );

  /// Optional [onPointTap] / [selectedPointIndex] are presentation-only passthrough.
  static ReportChartConfig toCashFlowTrendChart(
    FinancialDashboardCashFlowTimeSeries timeSeries, {
    void Function(ReportChartPoint point, String seriesId)? onPointTap,
    int? selectedPointIndex,
  }) {
    final granularity = timeSeries.granularity;
    final rawLabels = timeSeries.buckets.map((b) => b.label);
    final bucketCount = timeSeries.buckets.length;

    final inflowPoints = <ReportChartPoint>[];
    final outflowPoints = <ReportChartPoint>[];
    for (final bucket in timeSeries.buckets) {
      final label = _formatBucketLabel(
        bucket.label,
        granularity,
        bucketCount: bucketCount,
        allRawLabels: rawLabels,
      );
      inflowPoints.add(ReportChartPoint(label: label, value: bucket.inflow));
      outflowPoints.add(ReportChartPoint(label: label, value: bucket.outflow));
    }

    return ReportChartConfig(
      title: '\u0627\u062a\u062c\u0627\u0647 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
      type: ReportChartType.bar,
      yAxisFormatter: _yAxisLabel,
      emptyMessage: _kTrendEmptyMessage,
      onPointTap: onPointTap,
      selectedPointIndex: selectedPointIndex,
      series: [
        ReportChartSeries(
          id: 'inflow',
          label: _kTrendLegendInflow,
          color: AppColors.success,
          points: inflowPoints,
        ),
      ],
      secondarySeries: ReportChartSeries(
        id: 'outflow',
        label: _kTrendLegendOutflow,
        color: AppColors.error,
        points: outflowPoints,
      ),
    );
  }

  /// Optional [onPointTap] / [selectedPointIndex] are presentation-only passthrough.
  static ReportChartConfig toCashFlowCompositionChart(
    FinancialDashboardCashFlowBreakdown breakdown, {
    void Function(ReportChartPoint point, String seriesId)? onPointTap,
    int? selectedPointIndex,
  }) {
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
      yAxisFormatter: _tooltipMoney,
      emptyMessage: _kCompositionEmptyMessage,
      onPointTap: onPointTap,
      selectedPointIndex: selectedPointIndex,
      series: [
        ReportChartSeries(
          id: 'composition',
          label: '\u0628\u0646\u0648\u062f \u0627\u0644\u062a\u062f\u0641\u0642',
          color: AppColors.primary,
          points: points,
        ),
      ],
    );
  }
}