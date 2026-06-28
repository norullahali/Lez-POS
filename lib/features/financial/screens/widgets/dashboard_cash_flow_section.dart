import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../../reports/modules/shared/analytics_formatters.dart';
import '../../models/financial_dashboard_cash_flow.dart';
import '../../providers/dashboard_providers.dart';
import 'dashboard_kpi_tile.dart';

/// Cash Flow KPI section -- watches [dashboardCashFlowProvider] only.
class DashboardCashFlowSection extends ConsumerWidget {
  const DashboardCashFlowSection({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cashFlowAsync = ref.watch(dashboardCashFlowProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '\u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: 8),
        ReportAsyncBody<FinancialDashboardCashFlow>(
          asyncValue: cashFlowAsync,
          onRetry: onRefresh,
          loadingStyle: ReportLoadingStyle.skeletonMetrics,
          dataBuilder: (_, cashFlow) => _CashFlowKpiGrid(cashFlow: cashFlow),
        ),
      ],
    );
  }
}

class _CashFlowKpiGrid extends StatelessWidget {
  const _CashFlowKpiGrid({required this.cashFlow});

  final FinancialDashboardCashFlow cashFlow;

  static Color _netCashFlowColor(double net) {
    if (net > 0) return AppColors.success;
    if (net < 0) return AppColors.error;
    return AppColors.textSecondary;
  }

  static Color _cashBalanceColor(double balance) {
    if (balance < 0) return AppColors.error;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.6,
      children: [
        DashboardKpiTile(
          title: '\u0627\u0644\u0631\u0635\u064a\u062f \u0627\u0644\u0646\u0642\u062f\u064a',
          subtitle: '\u0644\u0627 \u064a\u062a\u0623\u062b\u0631 \u0628\u0627\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629',
          value: AnalyticsFormatters.money(cashFlow.cashBalance),
          icon: Icons.account_balance_rounded,
          color: _cashBalanceColor(cashFlow.cashBalance),
        ),
        DashboardKpiTile(
          title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u062f\u0627\u062e\u0644',
          value: AnalyticsFormatters.money(cashFlow.totalInflow),
          icon: Icons.arrow_circle_down_rounded,
          color: AppColors.success,
        ),
        DashboardKpiTile(
          title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u062e\u0631\u062c',
          value: AnalyticsFormatters.money(cashFlow.totalOutflow),
          icon: Icons.arrow_circle_up_rounded,
          color: AppColors.error,
        ),
        DashboardKpiTile(
          title: '\u0635\u0627\u0641\u064a \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
          value: AnalyticsFormatters.money(cashFlow.netCashFlow),
          icon: Icons.sync_alt_rounded,
          color: _netCashFlowColor(cashFlow.netCashFlow),
        ),
      ],
    );
  }
}