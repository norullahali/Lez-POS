import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../models/financial_dashboard_cash_analytics.dart';
import '../../providers/dashboard_providers.dart';
import '../../widgets/dashboard_analytics_insights_builder.dart';
import '../../widgets/dashboard_financial_alert.dart';
import '../../widgets/dashboard_financial_alerts_builder.dart';
import '../../widgets/dashboard_alert_card.dart';

const _kAlertSpacing = 10.0;
const _kTitleGap = 8.0;

/// Financial alerts section — watches certified dashboard providers only.
///
/// Phase 5.3.5: presentation-only attention highlights from analytics,
/// optional period cash-flow KPI, and existing insights. No drill-down or
/// mutations.
///
/// **Provider reuse:** shares [dashboardCashAnalyticsProvider] with analytics
/// and insights sections; reads [dashboardCashFlowProvider] with `.valueOrNull`
/// only (period net KPI already loaded upstream — no new SQL path).
/// Riverpod deduplicates analytics fetch — no extra repository queries.
///
/// **Rebuild scope:** alerts and insights are rebuilt in `dataBuilder` when
/// analytics async data changes; no local mutable cache.
///
/// **Accepted trade-off:** insights are built here for alert concentration
/// reuse; [DashboardInsightsSection] builds independently — CPU-only
/// duplication, not SQL duplication.
class DashboardAlertsSection extends ConsumerWidget {
  const DashboardAlertsSection({super.key, required this.onRefresh});

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
    final cashFlow = ref.watch(dashboardCashFlowProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '\u062a\u0646\u0628\u064a\u0647\u0627\u062a \u0645\u0627\u0644\u064a\u0629',
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
            final alerts = DashboardFinancialAlertsBuilder.fromContext(
              analytics: analytics,
              cashFlow: cashFlow,
              insights: insights,
            );
            return _AlertsList(alerts: alerts);
          },
        ),
      ],
    );
  }
}

/// Renders alert cards or a read-only empty-state message.
class _AlertsList extends StatelessWidget {
  const _AlertsList({required this.alerts});

  final List<DashboardFinancialAlert> alerts;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Text(
            '\u0644\u0627 \u062a\u0648\u062c\u062f \u062a\u0646\u0628\u064a\u0647\u0627\u062a \u062a\u062a\u0637\u0644\u0628 \u0627\u0644\u0627\u0646\u062a\u0628\u0627\u0647 \u0644\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629',
            style: DashboardAlertsSection._emptyMessageStyle,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < alerts.length; i++) ...[
          if (i > 0) const SizedBox(height: _kAlertSpacing),
          DashboardAlertCard(alert: alerts[i]),
        ],
      ],
    );
  }
}
