import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'analytics_business_health.dart';
import 'advanced_analytics_models.dart';
import 'analytics_formatters.dart';
import 'analytics_kpi_builder.dart';
import '../../core/models/report_metric_model.dart';
import '../../core/widgets/report_metric_grid.dart';
import 'advanced_analytics_providers.dart';
import 'comparison_metric_card.dart';
import 'analytics_comparison.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExecutiveDashboardPanel extends ConsumerWidget {
  const ExecutiveDashboardPanel({super.key, required this.data});

  final ExecutiveDashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparison = ref.watch(executiveComparisonProvider).valueOrNull;
    final categories = ref.watch(categoryPerformanceProvider).valueOrNull;
    final velocity = ref.watch(productVelocityProvider).valueOrNull;
    final employees = ref.watch(employeePerformanceProvider).valueOrNull;

    final insights = AnalyticsBusinessHealth.evaluate(
      exec: data,
      comparison: comparison,
      categories: categories,
      velocity: velocity,
      employees: employees,
    );

    final revenueDelta = comparison != null
        ? ComparisonDelta.compute(comparison.previous.revenue, comparison.current.revenue)
        : null;

    return SingleChildScrollView(
      key: const PageStorageKey('executive_dashboard_scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth > 1100 ? 3 : (c.maxWidth > 700 ? 2 : 1);
              return ReportMetricGrid(
                crossAxisCount: cols,
                childAspectRatio: cols == 1 ? 2.8 : 2.2,
                metrics: [
                  AnalyticsKpi.currency(
                    title: 'إجمالي الإيراد',
                    value: data.totalRevenue,
                    icon: Icons.payments_rounded,
                    color: AppColors.primary,
                    trendPercent: revenueDelta?.percent,
                    trendSemantic: revenueDelta?.semantic,
                  ),
                  AnalyticsKpi.currency(
                    title: 'إجمالي الربح',
                    value: data.totalProfit,
                    icon: Icons.trending_up_rounded,
                    color: AppColors.success,
                    trendPercent: comparison?.profitChangePercent,
                  ),
                  AnalyticsKpi.currency(
                    title: 'صافي التدفق',
                    value: data.netCashFlow,
                    icon: Icons.account_balance_wallet_rounded,
                    color: AppColors.info,
                    trendPercent: comparison?.cashFlowChangePercent,
                  ),
                  AnalyticsKpi.percent(
                    title: 'نسبة المرتجعات',
                    value: data.returnRatePercent,
                    icon: Icons.undo_rounded,
                    color: data.returnRatePercent >= 10 ? AppColors.error : AppColors.warning,
                    trendPercent: comparison?.returnRateChangePoints,
                    invertTrend: true,
                  ),
                  AnalyticsKpi.currency(
                    title: 'قيمة المخزون',
                    value: data.inventoryValue,
                    icon: Icons.warehouse_rounded,
                    color: AppColors.accent,
                  ),
                  AnalyticsKpi.text(
                    title: 'ذمم مدينة / دائنة',
                    value:
                        '${AnalyticsFormatters.money(data.receivableDebts)} / ${AnalyticsFormatters.money(data.payableDebts)}',
                    icon: Icons.balance_rounded,
                    color: AppColors.error,
                  ),
                  AnalyticsKpi.text(title: 'أفضل منتج', value: data.topProductName, icon: Icons.star_rounded),
                  AnalyticsKpi.text(title: 'أفضل عميل', value: data.topCustomerName, icon: Icons.person_rounded, color: AppColors.accent),
                  AnalyticsKpi.text(title: 'أفضل كاشير', value: data.topCashierName, icon: Icons.badge_rounded, color: AppColors.info),
                ],
              );
            },
          ),
          if (comparison != null) ...[
            const SizedBox(height: 20),
            Text('مقارنة سريعة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth > 900 ? 2 : 1;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: cols == 1 ? 2.6 : 2.2,
                  children: [
                    ComparisonMetricCard(title: 'الإيراد', delta: ComparisonDelta.compute(comparison.previous.revenue, comparison.current.revenue)),
                    ComparisonMetricCard(title: 'الربح', delta: ComparisonDelta.compute(comparison.previous.profit, comparison.current.profit)),
                    ComparisonMetricCard(
                      title: 'نسبة المرتجعات',
                      delta: ComparisonDelta.compute(comparison.previous.returnRate, comparison.current.returnRate),
                      invertGrowth: true,
                      formatValue: (v) => AnalyticsFormatters.pct(v),
                    ),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 24),
          Text('صحة الأعمال', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...insights.map((i) => _InsightTile(insight: i)),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight});
  final BusinessHealthInsight insight;

  @override
  Widget build(BuildContext context) {
    final color = switch (insight.semantic) {
      ReportTrendSemantic.positive => AppColors.success,
      ReportTrendSemantic.negative => AppColors.error,
      ReportTrendSemantic.warning => AppColors.warning,
      ReportTrendSemantic.neutral => AppColors.info,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(insight.icon, color: color, size: 20),
        ),
        title: Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(insight.message),
      ),
    );
  }
}
