import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/charts/report_chart_card.dart';
import '../../../reports/core/models/report_chart_models.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../models/financial_dashboard_cash_analytics.dart';
import '../../providers/dashboard_filter_provider.dart';
import '../../providers/dashboard_providers.dart';
import '../../widgets/dashboard_analytics_chart_selection.dart';
import '../../widgets/dashboard_analytics_drill_down.dart';
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
/// **Presentation:** mapping via [FinancialDashboardChartMapper], rendering via
/// [ReportChartCard]. Phase 5.3.3.1: local selection + feedback. Phase 5.3.3.2:
/// drill-down callbacks only -- no navigation state in providers.
///
/// **Navigation boundary:** [_AnalyticsChartCards] owns selection; parent wires
/// [DashboardAnalyticsDrillDown] with `ref.read(dashboardFilterProvider)` at
/// callback invocation (not watched -- avoids analytics section rebuilds on
/// filter edits).
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
          dataBuilder: (_, analytics) => _AnalyticsChartCards(
            analytics: analytics,
            onDrillDown: (selection) => _navigateDrillDown(
              context: context,
              ref: ref,
              analytics: analytics,
              selection: selection,
            ),
            canDrillDown: (selection) => _canDrillDown(
              ref: ref,
              analytics: analytics,
              selection: selection,
            ),
          ),
        ),
      ],
    );
  }

  /// Reads dashboard filter at tap time -- does not add a provider watch.
  static void _navigateDrillDown({
    required BuildContext context,
    required WidgetRef ref,
    required FinancialDashboardCashAnalytics analytics,
    required DashboardAnalyticsChartSelection selection,
  }) {
    DashboardAnalyticsDrillDown.navigateToCashLedger(
      context: context,
      ref: ref,
      dashboardFilter: ref.read(dashboardFilterProvider),
      analytics: analytics,
      selection: selection,
    );
  }

  /// Gates drill-down button visibility. [mapSelection] is O(1) over bucket/slice count.
  static bool _canDrillDown({
    required WidgetRef ref,
    required FinancialDashboardCashAnalytics analytics,
    required DashboardAnalyticsChartSelection selection,
  }) =>
      DashboardAnalyticsDrillDown.canNavigate(
        dashboardFilter: ref.read(dashboardFilterProvider),
        analytics: analytics,
        selection: selection,
      );
}

typedef _AnalyticsDrillDownCallback = void Function(
  DashboardAnalyticsChartSelection selection,
);

typedef _AnalyticsCanDrillDownCallback = bool Function(
  DashboardAnalyticsChartSelection selection,
);

/// Renders trend + composition cards from resolved [FinancialDashboardCashAnalytics].
class _AnalyticsChartCards extends StatefulWidget {
  const _AnalyticsChartCards({
    required this.analytics,
    required this.onDrillDown,
    required this.canDrillDown,
  });

  final FinancialDashboardCashAnalytics analytics;
  final _AnalyticsDrillDownCallback onDrillDown;
  final _AnalyticsCanDrillDownCallback canDrillDown;

  @override
  State<_AnalyticsChartCards> createState() => _AnalyticsChartCardsState();
}

/// Local presentation state for chart interaction (Phase 5.3.3.1) and drill-down
/// trigger (Phase 5.3.3.2).
///
/// Owns [_selection] only -- not persisted, not in Riverpod. Caches base chart
/// configs; selection rebuild applies [FinancialDashboardChartMapper.withInteractivity]
/// without remapping analytics data.
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

  void _handleDrillDown() {
    final selection = _selection;
    if (selection == null) return;
    widget.onDrillDown(selection);
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
    // canDrillDown re-evaluates mapSelection when feedback is visible -- bounded work.
    final showDrillDown = selection != null && widget.canDrillDown(selection);

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