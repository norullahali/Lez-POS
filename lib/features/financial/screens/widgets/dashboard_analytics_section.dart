import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/charts/report_chart_card.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../models/financial_dashboard_cash_analytics.dart';
import '../../providers/dashboard_providers.dart';
import '../../widgets/financial_dashboard_chart_mapper.dart';

const _kChartHeight = 320.0;
const _kChartSpacing = 12.0;

/// Analytics chart section -- watches [dashboardCashAnalyticsProvider] only.
///
/// Presentation only: mapping via [FinancialDashboardChartMapper], rendering via
/// [ReportChartCard]. Read-only -- no onPointTap / drill-down (Phase 5.3).
/// [_AnalyticsChartCards] is [StatelessWidget] with no [WidgetRef] access.
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
        const SizedBox(height: 8),
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

class _AnalyticsChartCards extends StatelessWidget {
  const _AnalyticsChartCards({required this.analytics});

  final FinancialDashboardCashAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final trendConfig =
        FinancialDashboardChartMapper.toCashFlowTrendChart(analytics.timeSeries);
    final compositionConfig =
        FinancialDashboardChartMapper.toCashFlowCompositionChart(analytics.breakdown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _kChartHeight,
          child: ReportChartCard(config: trendConfig),
        ),
        const SizedBox(height: _kChartSpacing),
        SizedBox(
          height: _kChartHeight,
          child: ReportChartCard(config: compositionConfig),
        ),
      ],
    );
  }
}