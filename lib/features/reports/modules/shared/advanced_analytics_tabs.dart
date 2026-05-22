import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../core/charts/report_chart_card.dart';
import '../../core/filters/report_filter_provider.dart';
import '../../core/models/report_chart_models.dart';
import '../../core/models/report_date_preset.dart';
import '../../core/models/report_drill_down.dart';
import '../../core/models/report_tab_id.dart';
import '../../core/services/report_drill_down_actions.dart';
import '../../core/widgets/report_async_body.dart';
import '../../core/widgets/report_metric_grid.dart';
import '../../core/widgets/report_table_widgets.dart';
import 'analytics_export_helper.dart';
import 'analytics_module_scaffold.dart';
import 'analytics_permission_gate.dart';
import 'analytics_export_formatter.dart';
import 'analytics_filter_utils.dart';
import 'analytics_formatters.dart';
import 'analytics_kpi_builder.dart';
import 'analytics_velocity_classifier.dart';
import 'comparison_metric_card.dart';
import 'analytics_comparison.dart';
import 'executive_dashboard_panel.dart';
import 'advanced_analytics_models.dart';
import 'advanced_analytics_providers.dart';
import 'hourly_heatmap_widget.dart';

class ProfitAnalysisTab extends ConsumerWidget {
  const ProfitAnalysisTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profitAnalysisProvider);
    final filter = ref.reportFilter(ReportTabId.profitAnalysis);

    return AnalyticsPermissionGate(
      requiresFinancial: true,
      requiresInventory: false,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<ProfitAnalysisData>(
        tabId: ReportTabId.profitAnalysis,
        asyncValue: async,
        onRetry: () => ref.invalidate(profitAnalysisProvider),
        loadingStyle: ReportLoadingStyle.skeletonMetrics,
        onExport: async.hasValue
            ? () => AnalyticsExportHelper.exportCsv(
                  context: context,
                  ref: ref,
                  reportId: 'profit_analysis',
                  titleAr: 'تحليل الأرباح',
                  filter: filter,
                  headers: const ['المقياس', 'القيمة'],
                  rows: AnalyticsExportFormatter.metricSection({
                    'إجمالي الإيراد': async.requireValue.grossRevenue,
                    'التكلفة التقديرية': async.requireValue.estimatedCost,
                    'إجمالي الربح': async.requireValue.grossProfit,
                    'هامش الربح %': async.requireValue.profitMarginPercent,
                  }),
                )
            : null,
        builder: (context, data) {
          final chart = ReportChartConfig(
            title: 'الإيراد مقابل التكلفة',
            type: ReportChartType.trend,
            yAxisFormatter: (v) => nfInt.format(v),
            series: [
              ReportChartSeries(
                id: 'revenue',
                label: 'الإيراد',
                color: AppColors.primary,
                points: data.trend
                    .map((p) => ReportChartPoint(label: p.label, value: p.primary))
                    .toList(),
              ),
            ],
            secondarySeries: ReportChartSeries(
              id: 'cost',
              label: 'التكلفة',
              color: AppColors.warning,
              points: data.trend
                  .map((p) => ReportChartPoint(label: p.label, value: p.secondary ?? 0))
                  .toList(),
            ),
          );

          return SingleChildScrollView(
            child: Column(
              children: [
                ReportMetricGrid(
                  metrics: [
                    AnalyticsKpi.currency(title: 'إجمالي الإيراد', value: data.grossRevenue, icon: Icons.payments_rounded, color: AppColors.primary),
                    AnalyticsKpi.currency(title: 'التكلفة التقديرية', value: data.estimatedCost, icon: Icons.inventory_2_rounded, color: AppColors.warning),
                    AnalyticsKpi.currency(title: 'إجمالي الربح', value: data.grossProfit, icon: Icons.trending_up_rounded, color: AppColors.success),
                    AnalyticsKpi.percent(title: 'هامش الربح', value: data.profitMarginPercent, icon: Icons.percent_rounded, color: AppColors.accent),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(height: 320, child: ReportChartCard(config: chart)),
                const SizedBox(height: 16),
                ReportTableCard(
                  title: 'أعلى المنتجات ربحاً',
                  columns: const [
                    DataColumn(label: Text('المنتج')),
                    DataColumn(label: Text('الربح'), numeric: true),
                    DataColumn(label: Text('الهامش %'), numeric: true),
                  ],
                  rows: data.topProfitable.map((p) => _productProfitRow(context, ref, p)).toList(),
                ),
                const SizedBox(height: 12),
                ReportTableCard(
                  title: 'أقل هامش ربح',
                  columns: const [
                    DataColumn(label: Text('المنتج')),
                    DataColumn(label: Text('الربح'), numeric: true),
                    DataColumn(label: Text('الهامش %'), numeric: true),
                  ],
                  rows: data.lowestMargin.map((p) => _productProfitRow(context, ref, p)).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  DataRow _productProfitRow(BuildContext context, WidgetRef ref, ProductProfitRow p) {
    return ReportDrillDownActions.interactiveRow(
      onSelectChanged: ReportDrillDownActions.rowHandler(
        context,
        ref,
        target: p.productId == null
            ? null
            : ReportDrillDownTarget(type: ReportDrillDownEntityType.product, id: p.productId!),
      ),
      cells: [
        DataCell(Text(p.name)),
        DataCell(Text('${nfInt.format(p.profit)} د.ع')),
        DataCell(Text('${p.marginPercent.toStringAsFixed(1)}%')),
      ],
    );
  }
}

class CashFlowTab extends ConsumerWidget {
  const CashFlowTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cashFlowProvider);
    final filter = ref.reportFilter(ReportTabId.cashFlow);

    return AnalyticsPermissionGate(
      requiresFinancial: true,
      requiresInventory: false,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<CashFlowData>(
        tabId: ReportTabId.cashFlow,
        asyncValue: async,
        onRetry: () => ref.invalidate(cashFlowProvider),
        onExport: async.hasValue
            ? () => AnalyticsExportHelper.exportCsv(
                  context: context,
                  ref: ref,
                  reportId: 'cash_flow',
                  titleAr: 'التدفق النقدي',
                  filter: filter,
                  headers: const ['البند', 'القيمة'],
                  rows: AnalyticsExportFormatter.metricSection({
                    'التدفق الداخل': async.requireValue.totalInflow,
                    'التدفق الخارج': async.requireValue.totalOutflow,
                    'صافي التدفق': async.requireValue.netCashFlow,
                  }),
                )
            : null,
        builder: (context, data) => SingleChildScrollView(
          child: Column(
            children: [
              ReportMetricGrid(
                metrics: [
                  AnalyticsKpi.currency(title: 'التدفق الداخل', value: data.totalInflow, icon: Icons.arrow_downward_rounded, color: AppColors.success),
                  AnalyticsKpi.currency(title: 'التدفق الخارج', value: data.totalOutflow, icon: Icons.arrow_upward_rounded, color: AppColors.error),
                  AnalyticsKpi.currency(title: 'صافي التدفق', value: data.netCashFlow, icon: Icons.account_balance_rounded, color: AppColors.primary),
                  AnalyticsKpi.currency(title: 'مصروفات (مستقبلي)', value: data.expensesPlaceholder, icon: Icons.receipt_long_rounded, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 12),
              ReportMetricGrid(
                crossAxisCount: 2,
                childAspectRatio: 3,
                metrics: [
                  AnalyticsKpi.currency(title: 'مبيعات نقدي', value: data.cashSales, icon: Icons.money_rounded, color: AppColors.warning),
                  AnalyticsKpi.currency(title: 'مبيعات بطاقة', value: data.cardSales, icon: Icons.credit_card_rounded, color: AppColors.accent),
                  AnalyticsKpi.currency(title: 'تحصيلات العملاء', value: data.customerCollections, icon: Icons.people_rounded, color: AppColors.info),
                  AnalyticsKpi.currency(title: 'مدفوعات الموردين', value: data.supplierPayments, icon: Icons.local_shipping_rounded, color: AppColors.error),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReturnImpactTab extends ConsumerWidget {
  const ReturnImpactTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(returnImpactProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: false,
      requiresInventory: false,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<ReturnImpactData>(
        tabId: ReportTabId.returnImpact,
        asyncValue: async,
        onRetry: () => ref.invalidate(returnImpactProvider),
        loadingStyle: ReportLoadingStyle.skeletonChart,
        builder: (context, data) => SingleChildScrollView(
          child: Column(
            children: [
              ReportMetricGrid(
                metrics: [
                  AnalyticsKpi.currency(title: 'إجمالي المرتجعات', value: data.totalReturnedAmount, icon: Icons.undo_rounded, color: AppColors.error),
                  AnalyticsKpi.percent(title: 'نسبة المرتجعات', value: data.returnRatePercent, icon: Icons.percent_rounded, color: AppColors.warning, invertTrend: true),
                  AnalyticsKpi.currency(title: 'صافي الإيراد', value: data.netRevenueAfterReturns, icon: Icons.payments_rounded, color: AppColors.primary),
                  AnalyticsKpi.count(title: 'كامل / جزئي', value: data.fullReturnCount, icon: Icons.sync_alt_rounded, color: AppColors.info, subtitle: '${data.partialReturnCount} جزئي'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 280,
                child: ReportChartCard(
                  config: ReportChartConfig(
                    title: 'اتجاه المرتجعات',
                    type: ReportChartType.trend,
                    yAxisFormatter: (v) => nfInt.format(v),
                    series: [
                      ReportChartSeries(
                        id: 'returns',
                        label: 'المرتجعات',
                        color: AppColors.error,
                        points: data.trend.map((p) => ReportChartPoint(label: p.label, value: p.primary)).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ReportTableCard(
                title: 'أكثر المنتجات إرجاعاً',
                columns: const [
                  DataColumn(label: Text('المنتج')),
                  DataColumn(label: Text('العدد'), numeric: true),
                  DataColumn(label: Text('القيمة'), numeric: true),
                ],
                rows: data.topReturnedProducts.map((r) => ReportDrillDownActions.interactiveRow(
                  onSelectChanged: ReportDrillDownActions.rowHandler(context, ref, target: r.id == null ? null : ReportDrillDownTarget(type: ReportDrillDownEntityType.product, id: r.id!)),
                  cells: [DataCell(Text(r.label)), DataCell(Text('${r.count}')), DataCell(Text('${nfInt.format(r.amount)} د.ع'))],
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InventoryMovementTab extends ConsumerWidget {
  const InventoryMovementTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inventoryMovementProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: false,
      requiresInventory: true,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<InventoryMovementData>(
        tabId: ReportTabId.inventoryMovement,
        asyncValue: async,
        onRetry: () => ref.invalidate(inventoryMovementProvider),
        loadingStyle: ReportLoadingStyle.skeletonChart,
        builder: (context, data) => SingleChildScrollView(
          child: Column(
            children: [
              ReportMetricGrid(
                metrics: [
                  AnalyticsKpi.count(title: 'وارد', value: data.stockIn, icon: Icons.add_box_rounded, color: AppColors.success),
                  AnalyticsKpi.count(title: 'صادر', value: data.stockOut, icon: Icons.indeterminate_check_box_rounded, color: AppColors.error),
                  AnalyticsKpi.count(title: 'مرتجعات وارد', value: data.returnsIn, icon: Icons.undo_rounded, color: AppColors.warning),
                  AnalyticsKpi.count(
                    title: 'مخزون راكد',
                    value: data.deadInventoryCount,
                    icon: Icons.warning_amber_rounded,
                    color: AppColors.error,
                    subtitle: VelocityClassifier.turnoverLabel(data.turnoverEstimate),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ReportTableCard(
                title: 'مخزون راكد',
                columns: const [
                  DataColumn(label: Text('المنتج')),
                  DataColumn(label: Text('الكمية'), numeric: true),
                  DataColumn(label: Text('القيمة'), numeric: true),
                ],
                rows: data.deadStock.map((r) => ReportDrillDownActions.interactiveRow(
                  onSelectChanged: ReportDrillDownActions.rowHandler(context, ref, target: r.productId == null ? null : ReportDrillDownTarget(type: ReportDrillDownEntityType.product, id: r.productId!)),
                  cells: [DataCell(Text(r.name)), DataCell(Text(nfInt.format(r.stock))), DataCell(Text('${nfInt.format(r.value)} د.ع'))],
                )).toList(),
                isEmpty: data.deadStock.isEmpty,
                emptyMessage: 'لا يوجد مخزون راكد في هذه الفترة',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TaxReportsTab extends ConsumerWidget {
  const TaxReportsTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(taxReportProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: true,
      requiresInventory: false,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<TaxReportData>(
        tabId: ReportTabId.taxReports,
        asyncValue: async,
        onRetry: () => ref.invalidate(taxReportProvider),
        builder: (context, data) {
          if (!data.taxEnabled) {
            return const Center(child: Text('الضريبة معطلة في إعدادات الفاتورة — لا توجد بيانات ضريبية'));
          }
          return SingleChildScrollView(
            child: ReportMetricGrid(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              metrics: [
                AnalyticsKpi.currency(title: 'المبيعات الخاضعة', value: data.taxableSales, icon: Icons.receipt_rounded, color: AppColors.primary),
                AnalyticsKpi.currency(title: 'الضريبة التقديرية', value: data.estimatedTaxCollected, icon: Icons.account_balance_rounded, color: AppColors.success),
              ],
            ),
          );
        },
      ),
    );
  }
}

class EmployeePerformanceTab extends ConsumerWidget {
  const EmployeePerformanceTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(employeePerformanceProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: false,
      requiresInventory: false,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<List<EmployeePerformanceRow>>(
        tabId: ReportTabId.employeePerformance,
        asyncValue: async,
        onRetry: () => ref.invalidate(employeePerformanceProvider),
        loadingStyle: ReportLoadingStyle.skeletonTable,
        isEmpty: (rows) => rows.isEmpty,
        builder: (context, rows) => ReportTableCard(
          title: 'أداء الموظفين',
          columns: const [
            DataColumn(label: Text('الموظف')),
            DataColumn(label: Text('الفواتير'), numeric: true),
            DataColumn(label: Text('المبيعات'), numeric: true),
            DataColumn(label: Text('متوسط الفاتورة'), numeric: true),
          ],
          rows: rows.map((e) => ReportDrillDownActions.interactiveRow(
            onSelectChanged: ReportDrillDownActions.rowHandler(
              context,
              ref,
              target: ReportDrillDownTarget(
                type: ReportDrillDownEntityType.user,
                id: e.userId,
                label: e.name,
              ),
            ),
            cells: [
              DataCell(Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text('${e.invoiceCount}')),
              DataCell(Text('${nfInt.format(e.salesAmount)} د.ع')),
              DataCell(Text('${nfInt.format(e.averageInvoice)} د.ع')),
            ],
          )).toList(),
        ),
      ),
    );
  }
}

class HourlyHeatmapTab extends ConsumerWidget {
  const HourlyHeatmapTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hourlySalesProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: false,
      requiresInventory: false,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<List<HourlySalesPoint>>(
        tabId: ReportTabId.hourlyHeatmap,
        asyncValue: async,
        onRetry: () => ref.invalidate(hourlySalesProvider),
        loadingStyle: ReportLoadingStyle.skeletonChart,
        builder: (context, points) => HourlyHeatmapWidget(points: points, nfInt: nfInt),
      ),
    );
  }
}

class CategoryPerformanceTab extends ConsumerWidget {
  const CategoryPerformanceTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoryPerformanceProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: false,
      requiresInventory: true,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<List<CategoryPerformanceRow>>(
        tabId: ReportTabId.categoryPerformance,
        asyncValue: async,
        onRetry: () => ref.invalidate(categoryPerformanceProvider),
        loadingStyle: ReportLoadingStyle.skeletonChart,
        isEmpty: (rows) => rows.isEmpty,
        builder: (context, rows) {
          final chart = ReportChartConfig(
            title: 'مساهمة التصنيفات',
            type: ReportChartType.pie,
            series: [
              ReportChartSeries(
                id: 'cat',
                label: 'الإيراد',
                color: AppColors.primary,
                points: rows.take(8).map((r) => ReportChartPoint(label: r.name, value: r.revenue)).toList(),
              ),
            ],
          );
          return SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 280, child: ReportChartCard(config: chart, showLegend: true)),
                const SizedBox(height: 12),
                ReportTableCard(
                  title: 'تفاصيل التصنيفات',
                  columns: const [
                    DataColumn(label: Text('التصنيف')),
                    DataColumn(label: Text('الكمية'), numeric: true),
                    DataColumn(label: Text('الإيراد'), numeric: true),
                    DataColumn(label: Text('المساهمة %'), numeric: true),
                  ],
                  rows: rows.map((r) => DataRow(cells: [
                    DataCell(Text(r.name)),
                    DataCell(Text(nfInt.format(r.quantitySold))),
                    DataCell(Text('${nfInt.format(r.revenue)} د.ع')),
                    DataCell(Text('${r.contributionPercent.toStringAsFixed(1)}%')),
                  ])).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ProductVelocityTab extends ConsumerWidget {
  const ProductVelocityTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(productVelocityProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: false,
      requiresInventory: true,
      requiresExecutive: false,
      child: AnalyticsModuleScaffold<ProductVelocityData>(
        tabId: ReportTabId.productVelocity,
        asyncValue: async,
        onRetry: () => ref.invalidate(productVelocityProvider),
        loadingStyle: ReportLoadingStyle.skeletonTable,
        builder: (context, data) => SingleChildScrollView(
          child: Column(
            children: [
              ReportTableCard(
                title: 'المنتجات سريعة الحركة',
                columns: const [DataColumn(label: Text('المنتج')), DataColumn(label: Text('الكمية'), numeric: true), DataColumn(label: Text('الإيراد'), numeric: true)],
                rows: data.fastMoving.map((r) => _velocityRow(context, ref, r)).toList(),
              ),
              const SizedBox(height: 12),
              ReportTableCard(
                title: 'المنتجات بطيئة الحركة',
                columns: const [DataColumn(label: Text('المنتج')), DataColumn(label: Text('مباع')), DataColumn(label: Text('المخزون'), numeric: true)],
                rows: data.slowMoving.map((r) => _velocityRow(context, ref, r, slow: true)).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _velocityRow(BuildContext context, WidgetRef ref, VelocityRow r, {bool slow = false}) {
    final cls = VelocityClassifier.classify(r, fromSlowList: slow);
    return ReportDrillDownActions.interactiveRow(
      onSelectChanged: ReportDrillDownActions.rowHandler(context, ref, target: r.productId == null ? null : ReportDrillDownTarget(type: ReportDrillDownEntityType.product, id: r.productId!)),
      cells: slow
          ? [
              DataCell(Row(children: [
                _VelocityBadge(cls: cls),
                const SizedBox(width: 6),
                Expanded(child: Text(r.name)),
              ])),
              DataCell(Text(nfInt.format(r.quantity))),
              DataCell(Text(nfInt.format(r.value))),
            ]
          : [
              DataCell(Row(children: [
                _VelocityBadge(cls: cls),
                const SizedBox(width: 6),
                Expanded(child: Text(r.name)),
              ])),
              DataCell(Text(nfInt.format(r.quantity))),
              DataCell(Text('${nfInt.format(r.value)} د.ع')),
            ],
    );
  }
}

class _VelocityBadge extends StatelessWidget {
  const _VelocityBadge({required this.cls});
  final VelocityClass cls;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cls.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cls.color.withValues(alpha: 0.5)),
      ),
      child: Text(cls.labelAr, style: TextStyle(fontSize: 10, color: cls.color, fontWeight: FontWeight.w700)),
    );
  }
}

class ExecutiveDashboardTab extends ConsumerWidget {
  const ExecutiveDashboardTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(executiveDashboardProvider);
    return AnalyticsPermissionGate(
      requiresFinancial: false,
      requiresInventory: false,
      requiresExecutive: true,
      child: AnalyticsModuleScaffold<ExecutiveDashboardData>(
        tabId: ReportTabId.executiveDashboard,
        asyncValue: async,
        onRetry: () => ref.invalidate(executiveDashboardProvider),
        loadingStyle: ReportLoadingStyle.skeletonMetrics,
        builder: (context, data) => ExecutiveDashboardPanel(data: data),
      ),
    );
  }
}

class ComparativeAnalyticsTab extends ConsumerWidget {
  const ComparativeAnalyticsTab({super.key, required this.nfInt});
  final NumberFormat nfInt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.reportFilter(ReportTabId.comparativeAnalytics);
    final async = ref.watch(comparativeAnalyticsProvider);

    return AnalyticsPermissionGate(
      requiresFinancial: true,
      requiresInventory: false,
      requiresExecutive: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in comparativePresets)
                  ChoiceChip(
                    label: Text(p.labelAr),
                    selected: filter.preset == p,
                    onSelected: (_) => ref.updateReportFilter(
                      ReportTabId.comparativeAnalytics,
                      comparativePresetFilter(p),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(filter.summaryAr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            Expanded(
              child: ReportAsyncBody<ComparativeAnalyticsData>(
                asyncValue: async,
                loadingStyle: ReportLoadingStyle.skeletonMetrics,
                onRetry: () => ref.invalidate(comparativeAnalyticsProvider),
                dataBuilder: (context, data) {
                  return LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth > 900 ? 2 : 1;
                      return GridView.count(
                        crossAxisCount: cols,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: cols == 1 ? 2.4 : 2.0,
                        children: [
                          ComparisonMetricCard(
                            title: 'الإيراد',
                            delta: ComparisonDelta.compute(data.previous.revenue, data.current.revenue),
                          ),
                          ComparisonMetricCard(
                            title: 'الربح',
                            delta: ComparisonDelta.compute(data.previous.profit, data.current.profit),
                          ),
                          ComparisonMetricCard(
                            title: 'صافي التدفق',
                            delta: ComparisonDelta.compute(data.previous.netCashFlow, data.current.netCashFlow),
                          ),
                          ComparisonMetricCard(
                            title: 'نسبة المرتجعات',
                            delta: ComparisonDelta.compute(data.previous.returnRate, data.current.returnRate),
                            invertGrowth: true,
                            formatValue: (v) => AnalyticsFormatters.pct(v),
                          ),
                          ComparisonMetricCard(
                            title: 'عدد الفواتير',
                            delta: ComparisonDelta.compute(
                              data.previous.invoiceCount.toDouble(),
                              data.current.invoiceCount.toDouble(),
                            ),
                            formatValue: (v) => AnalyticsFormatters.qty(v),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
