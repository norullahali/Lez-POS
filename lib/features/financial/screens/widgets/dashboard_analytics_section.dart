import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/charts/report_chart_card.dart';
import '../../../reports/core/models/report_chart_models.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../models/dashboard_filter.dart';
import '../../models/financial_dashboard_cash_analytics.dart';
import '../../providers/dashboard_filter_provider.dart';
import '../../providers/dashboard_providers.dart';
import '../../widgets/dashboard_analytics_chart_selection.dart';
import '../../widgets/dashboard_analytics_drill_down.dart';
import '../../widgets/dashboard_analytics_selection_feedback.dart';
import '../../widgets/dashboard_analytics_trend_bucket_presentation.dart';
import '../../widgets/financial_dashboard_chart_mapper.dart';

const _kChartHeight = 320.0;
const _kTrendChartHeightDense = 360.0;
const _kChartSpacing = 16.0;
const _kTitleGap = 8.0;
const _kDenseBucketThreshold = 20;
const _kFeedbackSpacing = 12.0;

/// Analytics chart section — watches [dashboardCashAnalyticsProvider] only.
///
/// Phase 5.3.3.3 caches trend bucket presentation metadata alongside chart configs
/// for accurate merged-bucket drill-down without label parsing at navigation time.
///
/// **Metadata lifecycle:** `_trendBucketPresentation` is owned by
/// [_AnalyticsChartCardsState], rebuilt in [_syncBaseConfigs] when analytics or
/// dashboard filter changes; selection is cleared on those updates.
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
          dataBuilder: (_, analytics) {
            final dashboardFilter = ref.read(dashboardFilterProvider);
            return _AnalyticsChartCards(
              analytics: analytics,
              dashboardFilter: dashboardFilter,
              onDrillDown: (selection, trendPresentation) => _navigateDrillDown(
                context: context,
                ref: ref,
                dashboardFilter: dashboardFilter,
                analytics: analytics,
                selection: selection,
                trendBucketPresentation: trendPresentation,
              ),
            );
          },
        ),
      ],
    );
  }

  static void _navigateDrillDown({
    required BuildContext context,
    required WidgetRef ref,
    required DashboardFilter dashboardFilter,
    required FinancialDashboardCashAnalytics analytics,
    required DashboardAnalyticsChartSelection selection,
    required List<DashboardTrendBucketPresentationMeta> trendBucketPresentation,
  }) {
    DashboardAnalyticsDrillDown.navigateToCashLedger(
      context: context,
      ref: ref,
      dashboardFilter: dashboardFilter,
      analytics: analytics,
      selection: selection,
      trendBucketPresentation: trendBucketPresentation,
    );
  }
}

typedef _AnalyticsDrillDownCallback = void Function(
  DashboardAnalyticsChartSelection selection,
  List<DashboardTrendBucketPresentationMeta> trendBucketPresentation,
);

class _AnalyticsChartCards extends StatefulWidget {
  const _AnalyticsChartCards({
    required this.analytics,
    required this.dashboardFilter,
    required this.onDrillDown,
  });

  final FinancialDashboardCashAnalytics analytics;
  final DashboardFilter dashboardFilter;
  final _AnalyticsDrillDownCallback onDrillDown;

  @override
  State<_AnalyticsChartCards> createState() => _AnalyticsChartCardsState();
}

class _AnalyticsChartCardsState extends State<_AnalyticsChartCards> {
  DashboardAnalyticsChartSelection? _selection;
  late ReportChartConfig _trendBase;
  late ReportChartConfig _compositionBase;

  /// Presentation-only drill-down metadata; one entry per trend bucket index.
  /// Regenerated with chart configs — not recomputed on selection-only rebuilds.
  late List<DashboardTrendBucketPresentationMeta> _trendBucketPresentation;

  FinancialDashboardCashAnalytics get analytics => widget.analytics;

  @override
  void initState() {
    super.initState();
    _syncBaseConfigs();
  }

  @override
  void didUpdateWidget(covariant _AnalyticsChartCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Analytics or filter change invalidates selection and cached presentation.
    if (oldWidget.analytics != widget.analytics ||
        oldWidget.dashboardFilter != widget.dashboardFilter) {
      _selection = null;
      _syncBaseConfigs();
    }
  }

  /// Rebuilds cached chart configs and trend bucket presentation together.
  ///
  /// Called from [initState] and [didUpdateWidget] only — not on local selection
  /// toggles — so metadata is generated once per analytics payload.
  void _syncBaseConfigs() {
    _trendBase =
        FinancialDashboardChartMapper.toCashFlowTrendChart(analytics.timeSeries);
    _compositionBase =
        FinancialDashboardChartMapper.toCashFlowCompositionChart(analytics.breakdown);
    _trendBucketPresentation =
        FinancialDashboardChartMapper.buildTrendBucketPresentationMetas(
      timeSeries: analytics.timeSeries,
      dashboardRange: widget.dashboardFilter.resolvedRange,
    );
  }

  static double _trendChartHeight(FinancialDashboardCashFlowTimeSeries series) =>
      series.buckets.length > _kDenseBucketThreshold
          ? _kTrendChartHeightDense
          : _kChartHeight;

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

  bool _canDrillDown(DashboardAnalyticsChartSelection selection) =>
      DashboardAnalyticsDrillDown.canNavigate(
        dashboardFilter: widget.dashboardFilter,
        analytics: analytics,
        selection: selection,
        trendBucketPresentation: _trendBucketPresentation,
      );

  void _handleDrillDown() {
    final selection = _selection;
    if (selection == null) return;
    widget.onDrillDown(selection, _trendBucketPresentation);
  }

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

    final selection = _selection;
    final showDrillDown =
        selection != null && _canDrillDown(selection);

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
        if (selection != null) ...[
          const SizedBox(height: _kFeedbackSpacing),
          DashboardAnalyticsSelectionFeedback(
            analytics: analytics,
            selection: selection,
            onClear: _clearSelection,
            onDrillDown: showDrillDown ? _handleDrillDown : null,
          ),
        ],
      ],
    );
  }
}
