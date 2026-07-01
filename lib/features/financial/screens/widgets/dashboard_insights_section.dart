import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../models/financial_dashboard_cash_analytics.dart';
import '../../providers/dashboard_providers.dart';
import '../../widgets/dashboard_analytics_insight.dart';
import '../../widgets/dashboard_analytics_insights_builder.dart';
import '../../widgets/dashboard_insight_card.dart';

const _kInsightSpacing = 10.0;
const _kTitleGap = 8.0;

/// Analytical insights section — watches [dashboardCashAnalyticsProvider] only.
///
/// Phase 5.3.4: presentation-only observations from certified analytics data.
/// No drill-down, no provider invalidation, no additional repository queries.
///
/// **Provider reuse:** shares [dashboardCashAnalyticsProvider] with
/// [DashboardAnalyticsSection]; Riverpod deduplicates the fetch — no extra SQL.
///
/// **Rebuild scope:** insights are rebuilt in `dataBuilder` when analytics async
/// data changes; no local mutable cache.
class DashboardInsightsSection extends ConsumerWidget {
  const DashboardInsightsSection({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static const _emptyMessageStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(dashboardCashAnalyticsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '\u0631\u0624\u0649 \u0645\u0627\u0644\u064a\u0629',
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: _kTitleGap),
        ReportAsyncBody<FinancialDashboardCashAnalytics>(
          asyncValue: analyticsAsync,
          onRetry: onRefresh,
          loadingStyle: ReportLoadingStyle.skeletonMetrics,
          dataBuilder: (_, analytics) {
            final insights =
                DashboardAnalyticsInsightsBuilder.fromAnalytics(analytics);
            return _InsightsList(insights: insights);
          },
        ),
      ],
    );
  }
}

/// Renders insight cards or a read-only empty-state message.
class _InsightsList extends StatelessWidget {
  const _InsightsList({required this.insights});

  final List<DashboardAnalyticsInsight> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Text(
            '\u0644\u0627 \u062a\u0648\u062c\u062f \u0645\u0644\u0627\u062d\u0638\u0627\u062a \u0643\u0627\u0641\u064a\u0629 \u0644\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629',
            style: DashboardInsightsSection._emptyMessageStyle,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < insights.length; i++) ...[
          if (i > 0) const SizedBox(height: _kInsightSpacing),
          DashboardInsightCard(insight: insights[i]),
        ],
      ],
    );
  }
}
