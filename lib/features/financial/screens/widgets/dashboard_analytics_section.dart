import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/charts/report_chart_card.dart';
import '../../../reports/core/models/report_chart_models.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../models/financial_dashboard_cash_analytics.dart';
import '../../providers/dashboard_providers.dart';
import '../../widgets/dashboard_analytics_chart_selection.dart';
import '../../widgets/dashboard_analytics_selection_feedback.dart';
import '../../widgets/financial_dashboard_chart_mapper.dart';

const _kChartHeight = 320.0;
const _kTrendChartHeightDense = 360.0;
const _kChartSpacing = 16.0;
const _kTitleGap = 8.0;
const _kDenseBucketThreshold = 20;
const _kFeedbackSpacing = 12.0;

/// Analytics chart section -- watches [dashboardCashAnalyticsProvider] only.
///
/// Presentation only: mapping via [FinancialDashboardChartMapper], rendering via
/// [ReportChartCard]. Phase 5.3.3.1 adds read-only chart selection feedback
/// without provider invalidation or drill-down navigation.
/// [_AnalyticsChartCards] holds local presentation selection state only.
class DashboardAnalyticsSection extends ConsumerWidget {
  const DashboardAnalyticsSection({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardCashAnalyticsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '\u0627\u0644\u062a\u062d\u0644\u064a\u0644\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: _kTitleGap),
        ReportAsyncBody<FinancialDashboardCashAnalytics>(
          asyncValue: analyticsAsync,
          onRetry: onRefresh,
          loadingStyle: ReportLoadingStyle.skeletonChart,
          dataBuilder: (_, analytics) => _AnalyticsChartCards(analytics: analytics),
        ),
      ],
    );
  }
}

/// Renders trend + composition cards from resolved [FinancialDashboardCashAnalytics].
class _AnalyticsChartCards extends StatefulWidget {
  const _AnalyticsChartCards({required this.analytics});

  final FinancialDashboardCashAnalytics analytics;

  @override
  State<_AnalyticsChartCards> createState() => _AnalyticsChartCardsState();
}

/// Local presentation state for read-only chart interaction (Phase 5.3.3.1).
///
/// Caches base chart configs and a single [DashboardAnalyticsChartSelection].
/// Selection clears when [FinancialDashboardCashAnalytics] changes (value equality).
/// No additional provider watches -- rebuild scope stays within this state object.
class _AnalyticsChartCardsState extends State<_AnalyticsChartCards> {
  DashboardAnalyticsChartSelection? _selection;
  late ReportChartConfig _trendBase;
  late ReportChartConfig _compositionBase;

  FinancialDashboardCashAnalytics get analytics => widget.analytics;

  @override
  void initState() {
    super.initState();
    _syncBaseConfigs();
  }

  @override
  void didUpdateWidget(covariant _AnalyticsChartCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analytics != widget.analytics) {
      _selection = null;
      _syncBaseConfigs();
    }
  }

  /// Rebuilds cached configs when analytics payload changes (not on selection).
  void _syncBaseConfigs() {
    _trendBase =
        FinancialDashboardChartMapper.toCashFlowTrendChart(analytics.timeSeries);
    _compositionBase =
        FinancialDashboardChartMapper.toCashFlowCompositionChart(analytics.breakdown);
  }

  static double _trendChartHeight(FinancialDashboardCashFlowTimeSeries series) =>
      series.buckets.length > _kDenseBucketThreshold
          ? _kTrendChartHeightDense
          : _kChartHeight;

  /// Resolves a tap target to a chart point index (label matches cached config).
  static int _pointIndexForLabel(ReportChartConfig config, String label) =>
      config.series.first.points.indexWhere((p) => p.label == label);

  int? get _selectedTrendIndex => switch (_selection) {
        DashboardTrendBucketSelection(:final bucketIndex) => bucketIndex,
        _ => null,
      };

  int? get _selectedCompositionIndex => switch (_selection) {
        DashboardCompositionSliceSelection(:final sliceIndex) => sliceIndex,
        _ => null,
      };

  void _onTrendPointTap(ReportChartPoint point, String seriesId) {
    final index = _pointIndexForLabel(_trendBase, point.label);
    if (index < 0) return;
    setState(() {
      _selection = switch (_selection) {
        DashboardTrendBucketSelection(bucketIndex: final i) when i == index => null,
        _ => DashboardTrendBucketSelection(bucketIndex: index),
      };
    });
  }

  void _onCompositionPointTap(ReportChartPoint point, String seriesId) {
    final index = _pointIndexForLabel(_compositionBase, point.label);
    if (index < 0) return;
    setState(() {
      _selection = switch (_selection) {
        DashboardCompositionSliceSelection(sliceIndex: final i) when i == index =>
          null,
        _ => DashboardCompositionSliceSelection(sliceIndex: index),
      };
    });
  }

  void _clearSelection() => setState(() => _selection = null);

  @override
  Widget build(BuildContext context) {
    final trendConfig = FinancialDashboardChartMapper.withInteractivity(
      _trendBase,
      onPointTap: _onTrendPointTap,
      selectedPointIndex: _selectedTrendIndex,
    );
    final compositionConfig = FinancialDashboardChartMapper.withInteractivity(
      _compositionBase,
      onPointTap: _onCompositionPointTap,
      selectedPointIndex: _selectedCompositionIndex,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _trendChartHeight(analytics.timeSeries),
          child: ReportChartCard(config: trendConfig),
        ),
        const SizedBox(height: _kChartSpacing),
        SizedBox(
          height: _kChartHeight,
          child: ReportChartCard(
            config: compositionConfig,
            showLegend: false,
          ),
        ),
        if (_selection != null) ...[
          const SizedBox(height: _kFeedbackSpacing),
          DashboardAnalyticsSelectionFeedback(
            analytics: analytics,
            selection: _selection!,
            onClear: _clearSelection,
          ),
        ],
      ],
    );
  }
}