import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../../reports/modules/shared/analytics_formatters.dart';
import '../../models/financial_dashboard_current_state.dart';
import '../../providers/dashboard_providers.dart';
import 'dashboard_kpi_tile.dart';

/// Supplementary KPI section -- watches [dashboardCurrentStateProvider] only.
class DashboardSupplementaryKpiSection extends ConsumerWidget {
  const DashboardSupplementaryKpiSection({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStateAsync = ref.watch(dashboardCurrentStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '\u0627\u0644\u0645\u0624\u0634\u0631\u0627\u062a \u0627\u0644\u062a\u0643\u0645\u064a\u0644\u064a\u0629',
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: 8),
        ReportAsyncBody<FinancialDashboardCurrentState>(
          asyncValue: currentStateAsync,
          onRetry: onRefresh,
          loadingStyle: ReportLoadingStyle.skeletonMetrics,
          dataBuilder: (_, state) => _SupplementaryKpiGrid(state: state),
        ),
      ],
    );
  }
}

class _SupplementaryKpiGrid extends StatelessWidget {
  const _SupplementaryKpiGrid({required this.state});

  final FinancialDashboardCurrentState state;

  static Color _sessionDifferenceColor(double difference) {
    if (difference > 0) return AppColors.success;
    if (difference < 0) return AppColors.error;
    return AppColors.textSecondary;
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
          title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0641\u062a\u0631\u0629',
          value: AnalyticsFormatters.money(state.totalSales),
          icon: Icons.point_of_sale_rounded,
          color: AppColors.primary,
        ),
        DashboardKpiTile(
          title: '\u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0628\u0637\u0627\u0642\u0627\u062a',
          value: AnalyticsFormatters.money(state.cardSales),
          icon: Icons.credit_card_rounded,
          color: AppColors.info,
        ),
        DashboardKpiTile(
          title: '\u062f\u064a\u0648\u0646 \u0627\u0644\u0639\u0645\u0644\u0627\u0621',
          subtitle: '\u0627\u0644\u062d\u0627\u0644\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629',
          value: AnalyticsFormatters.money(state.customerDebt),
          icon: Icons.people_rounded,
          color: AppColors.error,
        ),
        DashboardKpiTile(
          title: '\u062f\u064a\u0648\u0646 \u0627\u0644\u0645\u0648\u0631\u062f\u064a\u0646',
          subtitle: '\u0627\u0644\u062d\u0627\u0644\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629',
          value: AnalyticsFormatters.money(state.supplierDebt),
          icon: Icons.local_shipping_rounded,
          color: AppColors.warning,
        ),
        DashboardKpiTile(
          title: '\u0641\u0631\u0642 \u0627\u0644\u062c\u0644\u0633\u0627\u062a',
          value: AnalyticsFormatters.money(state.sessionDifference),
          icon: Icons.compare_arrows_rounded,
          color: _sessionDifferenceColor(state.sessionDifference),
        ),
      ],
    );
  }
}