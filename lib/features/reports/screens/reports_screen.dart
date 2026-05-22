// lib/features/reports/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../core/charts/report_chart_card.dart';
import '../core/exports/report_export_models.dart';
import '../core/exports/report_export_service.dart';
import '../core/filters/report_filter_provider.dart';
import '../core/models/report_chart_models.dart';
import '../core/models/report_date_preset.dart';
import '../core/models/report_drill_down.dart';
import '../core/models/report_filter_model.dart';
import '../core/models/report_metric_model.dart';
import '../core/models/report_tab_id.dart';
import '../core/services/report_drill_down_actions.dart';
import '../core/services/report_query_cache.dart';
import '../core/widgets/report_async_body.dart';
import '../core/widgets/report_error_view.dart';
import '../core/widgets/report_filter_bar.dart';
import '../core/widgets/report_loading_view.dart';
import '../core/widgets/report_metric_grid.dart';
import '../core/widgets/report_tab_keep_alive.dart';
import '../core/widgets/report_table_widgets.dart';
import '../providers/reports_provider.dart';
import '../../suppliers/providers/supplier_accounts_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  final _nf = NumberFormat('#,##0.##');
  final _nfInt = NumberFormat('#,##0');
  final _df = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    final initialIndex = ref.read(reportSessionProvider).activeTabIndex.clamp(0, 7);
    _tabCtrl = TabController(length: 8, vsync: this, initialIndex: initialIndex);
    _tabCtrl.addListener(_syncTabToSession);
  }

  void _syncTabToSession() {
    if (_tabCtrl.indexIsChanging) return;
    ref.read(reportSessionProvider.notifier).setActiveTab(_tabCtrl.index);
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_syncTabToSession);
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 24),
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.today_rounded), text: 'تقرير يومي'),
              Tab(icon: Icon(Icons.calendar_month_rounded), text: 'مبيعات شهرية'),
              Tab(icon: Icon(Icons.trending_up_rounded), text: 'أكثر المنتجات مبيعاً'),
              Tab(icon: Icon(Icons.warehouse_rounded), text: 'قيمة المخزون'),
              Tab(icon: Icon(Icons.local_shipping_rounded), text: 'مشتريات الموردين'),
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'أفضل العملاء'),
              Tab(icon: Icon(Icons.account_balance_wallet_rounded), text: 'الذمم المدينة'),
              Tab(icon: Icon(Icons.payment_rounded), text: 'الذمم الدائنة'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              ReportTabKeepAlive(child: _DailyReportTab(nf: _nf, nfInt: _nfInt, df: _df)),
              ReportTabKeepAlive(child: _MonthlySalesTab(nfInt: _nfInt)),
              ReportTabKeepAlive(child: _TopProductsTab(nf: _nf, nfInt: _nfInt)),
              ReportTabKeepAlive(child: _InventoryValueTab(nf: _nf, nfInt: _nfInt)),
              ReportTabKeepAlive(child: _PurchaseHistoryTab(nfInt: _nfInt)),
              ReportTabKeepAlive(child: _TopCustomersTab(nfInt: _nfInt)),
              ReportTabKeepAlive(child: _DebtReportTab(nfInt: _nfInt)),
              ReportTabKeepAlive(child: _PayableReportTab(nfInt: _nfInt)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyReportTab extends ConsumerWidget {
  final NumberFormat nf;
  final NumberFormat nfInt;
  final DateFormat df;

  const _DailyReportTab({required this.nf, required this.nfInt, required this.df});

  Future<void> _exportDaily(
    BuildContext context,
    WidgetRef ref,
    ReportFilterModel filter,
    Map<String, dynamic> data,
  ) async {
    final user = ref.read(authProvider).valueOrNull?.user?.username;
    final result = await ReportExportService.export(
      ReportExportRequest(
        metadata: ReportExportMetadata(
          reportId: 'daily_sales',
          titleAr: 'التقرير اليومي',
          generatedAt: DateTime.now(),
          filterSummary: filter.summaryAr(),
          generatedBy: user,
        ),
        format: ReportExportFormat.csv,
        headers: const ['المقياس', 'القيمة'],
        rows: [
          ['إجمالي المبيعات', '${data['total'] ?? 0}'],
          ['عدد الفواتير', '${data['count'] ?? 0}'],
          ['الربح المتوقع', '${data['profit'] ?? 0}'],
          ['مبيعات نقدي', '${data['cash'] ?? 0}'],
          ['مبيعات بطاقة', '${data['card'] ?? 0}'],
        ],
      ),
    );
    if (!context.mounted) return;
    final msg = result.filePath != null ? 'تم حفظ التقرير: ${result.filePath}' : (result.message ?? 'تعذر التصدير');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.reportFilter(ReportTabId.daily);
    final selectedDate = filter.resolveSingleDate();
    final dailyAsync = ref.watch(reportDailySalesProvider(selectedDate));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ReportFilterBar(
            mode: ReportFilterBarMode.singleDate,
            filter: filter,
            presets: const [
              ReportDatePreset.today,
              ReportDatePreset.yesterday,
              ReportDatePreset.custom,
            ],
            onFilterChanged: (f) => ref.updateReportFilter(ReportTabId.daily, f),
            onRefresh: () {
              ReportQueryCache.invalidatePrefix(ReportTabId.daily.cachePrefix);
              ref.invalidate(reportDailySalesProvider(selectedDate));
            },
            onExport: dailyAsync.hasValue
                ? () => _exportDaily(context, ref, filter, dailyAsync.requireValue)
                : null,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ReportAsyncBody<Map<String, dynamic>>(
              asyncValue: dailyAsync,
              loadingStyle: ReportLoadingStyle.skeletonMetrics,
              onRetry: () => ref.invalidate(reportDailySalesProvider(selectedDate)),
              dataBuilder: (context, data) {
                final total = (data['total'] as num?)?.toDouble() ?? 0;
                final count = (data['count'] as num?)?.toInt() ?? 0;
                final profit = (data['profit'] as num?)?.toDouble() ?? 0;
                final cash = (data['cash'] as num?)?.toDouble() ?? 0;
                final card = (data['card'] as num?)?.toDouble() ?? 0;
                return SingleChildScrollView(
                  key: const PageStorageKey('report_daily_scroll'),
                  child: ReportMetricGrid(
                    metrics: [
                      ReportMetricModel(
                        title: 'إجمالي المبيعات',
                        value: '${nfInt.format(total)} د.ع',
                        icon: Icons.point_of_sale_rounded,
                        color: AppColors.primary,
                      ),
                      ReportMetricModel(
                        title: 'عدد الفواتير',
                        value: '$count فاتورة',
                        icon: Icons.receipt_long_rounded,
                        color: AppColors.info,
                      ),
                      ReportMetricModel(
                        title: 'الربح المتوقع',
                        value: '${nfInt.format(profit)} د.ع',
                        icon: Icons.trending_up_rounded,
                        color: AppColors.success,
                      ),
                      ReportMetricModel(
                        title: 'مبيعات نقدي',
                        value: '${nfInt.format(cash)} د.ع',
                        icon: Icons.money_rounded,
                        color: AppColors.warning,
                      ),
                      ReportMetricModel(
                        title: 'مبيعات بطاقة',
                        value: '${nfInt.format(card)} د.ع',
                        icon: Icons.credit_card_rounded,
                        color: AppColors.accent,
                      ),
                      ReportMetricModel(
                        title: 'متوسط الفاتورة',
                        value: count > 0 ? '${nfInt.format(total / count)} د.ع' : '-',
                        icon: Icons.calculate_rounded,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopProductsTab extends ConsumerWidget {
  final NumberFormat nf;
  final NumberFormat nfInt;
  const _TopProductsTab({required this.nf, required this.nfInt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.reportFilter(ReportTabId.topProducts);
    final range = filter.resolveRange();
    final topAsync = ref.watch(reportTopProductsProvider(range));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ReportFilterBar(
            mode: ReportFilterBarMode.dateRange,
            filter: filter,
            showExport: false,
            onFilterChanged: (f) => ref.updateReportFilter(ReportTabId.topProducts, f, debounce: true),
            onRefresh: () {
              ReportQueryCache.invalidatePrefix(ReportTabId.topProducts.cachePrefix);
              ref.invalidate(reportTopProductsProvider(range));
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ReportAsyncBody<List<Map<String, dynamic>>>(
              asyncValue: topAsync,
              loadingStyle: ReportLoadingStyle.skeletonTable,
              onRetry: () => ref.invalidate(reportTopProductsProvider(range)),
              isEmpty: (products) => products.isEmpty,
              emptyIcon: Icons.bar_chart_rounded,
              emptyMessage: 'لا توجد مبيعات في هذه الفترة',
              dataBuilder: (context, products) => ReportTableCard(
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('المنتج')),
                  DataColumn(label: Text('الكمية المباعة'), numeric: true),
                  DataColumn(label: Text('الإيراد'), numeric: true),
                ],
                rows: products.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  final productId = p['product_id'] as int?;
                  return ReportDrillDownActions.interactiveRow(
                    onSelectChanged: ReportDrillDownActions.rowHandler(
                      context,
                      ref,
                      target: productId == null
                          ? null
                          : ReportDrillDownTarget(
                              type: ReportDrillDownEntityType.product,
                              id: productId,
                              label: p['name'] as String?,
                            ),
                    ),
                    cells: [
                      DataCell(CircleAvatar(
                        radius: 14,
                        backgroundColor: i < 3 ? AppColors.accent : AppColors.primary.withValues(alpha: 0.1),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: i < 3 ? Colors.white : AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )),
                      DataCell(Text(p['name'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(nf.format(p['total_qty'] ?? 0))),
                      DataCell(Text(
                        '${nfInt.format(p['total_revenue'] ?? 0)} د.ع',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- New Tabs ---

class _MonthlySalesTab extends ConsumerWidget {
  final NumberFormat nfInt;
  const _MonthlySalesTab({required this.nfInt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.reportFilter(ReportTabId.monthly);
    final year = filter.resolveYear();
    final monthlyAsync = ref.watch(reportMonthlySalesProvider(year));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ReportFilterBar(
            mode: ReportFilterBarMode.yearOnly,
            filter: filter,
            showExport: false,
            onFilterChanged: (f) => ref.updateReportFilter(ReportTabId.monthly, f),
            onRefresh: () {
              ReportQueryCache.invalidatePrefix(ReportTabId.monthly.cachePrefix);
              ref.invalidate(reportMonthlySalesProvider(year));
            },
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ReportAsyncBody<List<Map<String, dynamic>>>(
              asyncValue: monthlyAsync,
              loadingStyle: ReportLoadingStyle.skeletonChart,
              onRetry: () => ref.invalidate(reportMonthlySalesProvider(year)),
              isEmpty: (months) => months.isEmpty,
              emptyIcon: Icons.calendar_month_rounded,
              emptyMessage: 'لا توجد مبيعات في هذه السنة',
              dataBuilder: (context, months) {
                final fullMonths = List.generate(12, (i) {
                  final mStr = (i + 1).toString().padLeft(2, '0');
                  final existing = months.cast<Map<String,dynamic>?>().firstWhere((m) => m?['month'] == mStr, orElse: () => null);
                  return existing ?? {'month': mStr, 'invoice_count': 0, 'total_revenue': 0.0, 'total_profit': 0.0};
                });

                final chartConfig = ReportChartConfig(
                  title: 'المبيعات والأرباح الشهرية',
                  type: ReportChartType.bar,
                  yAxisFormatter: (v) => nfInt.format(v),
                  series: [
                    ReportChartSeries(
                      id: 'revenue',
                      label: 'الإيراد',
                      color: AppColors.primary,
                      points: fullMonths
                          .map((m) => ReportChartPoint(
                                label: m['month'] as String,
                                value: (m['total_revenue'] as num).toDouble(),
                              ))
                          .toList(),
                    ),
                  ],
                  secondarySeries: ReportChartSeries(
                    id: 'profit',
                    label: 'الربح',
                    color: AppColors.success,
                    points: fullMonths
                        .map((m) => ReportChartPoint(
                              label: m['month'] as String,
                              value: (m['total_profit'] as num).toDouble(),
                            ))
                        .toList(),
                  ),
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: ReportChartCard(config: chartConfig),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: ReportTableCard(
                        title: 'تفاصيل الأشهر',
                        columns: const [
                          DataColumn(label: Text('الشهر')),
                          DataColumn(label: Text('الفواتير'), numeric: true),
                          DataColumn(label: Text('ربح/إيراد'), numeric: true),
                        ],
                        rows: fullMonths.where((m) => (m['invoice_count'] as num) > 0).map((m) {
                          return DataRow(cells: [
                            DataCell(Text(m['month'] as String)),
                            DataCell(Text(m['invoice_count'].toString())),
                            DataCell(Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${nfInt.format(m['total_revenue'])} د.ع', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary)),
                                Text('${nfInt.format(m['total_profit'])} د.ع', style: const TextStyle(fontSize: 12, color: AppColors.success)),
                              ],
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryValueTab extends ConsumerWidget {
  final NumberFormat nf;
  final NumberFormat nfInt;
  const _InventoryValueTab({required this.nf, required this.nfInt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invAsync = ref.watch(reportInventoryValueProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: ReportAsyncBody<List<Map<String, dynamic>>>(
              asyncValue: invAsync,
              loadingStyle: ReportLoadingStyle.skeletonTable,
              onRetry: () => ref.invalidate(reportInventoryValueProvider),
              isEmpty: (products) => products.isEmpty,
              emptyIcon: Icons.warehouse_rounded,
              emptyMessage: 'لا يوجد مخزون مقيم حالياً',
              dataBuilder: (context, products) {
                final totalValue = products.fold<double>(0, (sum, p) => sum + (p['total_value'] as num).toDouble());

                return Column(
                  children: [
                    ReportMetricGrid(
                      crossAxisCount: 1,
                      childAspectRatio: 4,
                      metrics: [
                        ReportMetricModel(
                          title: 'إجمالي قيمة المخزون الحالية',
                          value: '${nfInt.format(totalValue)} د.ع',
                          icon: Icons.attach_money_rounded,
                          color: AppColors.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ReportTableCard(
                        columns: const [
                          DataColumn(label: Text('المنتج')),
                          DataColumn(label: Text('الباركود')),
                          DataColumn(label: Text('الكمية الحالية'), numeric: true),
                          DataColumn(label: Text('متوسط التكلفة'), numeric: true),
                          DataColumn(label: Text('إجمالي القيمة'), numeric: true),
                        ],
                        rows: products.map((p) {
                          final productId = p['product_id'] as int?;
                          return ReportDrillDownActions.interactiveRow(
                            onSelectChanged: ReportDrillDownActions.rowHandler(
                              context,
                              ref,
                              target: productId == null
                                  ? null
                                  : ReportDrillDownTarget(
                                      type: ReportDrillDownEntityType.product,
                                      id: productId,
                                      label: p['product_name'] as String?,
                                    ),
                            ),
                            cells: [
                              DataCell(Text(p['product_name'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(p['barcode'] as String? ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                              DataCell(Text(nf.format(p['current_stock'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text('${nf.format(p['cost_price'] ?? 0)} د.ع')),
                              DataCell(Text('${nfInt.format(p['total_value'] ?? 0)} د.ع', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseHistoryTab extends ConsumerWidget {
  final NumberFormat nfInt;
  const _PurchaseHistoryTab({required this.nfInt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.reportFilter(ReportTabId.purchases);
    final range = filter.resolveRange();
    final purchAsync = ref.watch(reportPurchasesProvider(range));

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ReportFilterBar(
            mode: ReportFilterBarMode.dateRange,
            filter: filter,
            showExport: false,
            onFilterChanged: (f) => ref.updateReportFilter(ReportTabId.purchases, f, debounce: true),
            onRefresh: () {
              ReportQueryCache.invalidatePrefix(ReportTabId.purchases.cachePrefix);
              ref.invalidate(reportPurchasesProvider(range));
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ReportAsyncBody<List<Map<String, dynamic>>>(
              asyncValue: purchAsync,
              loadingStyle: ReportLoadingStyle.skeletonTable,
              onRetry: () => ref.invalidate(reportPurchasesProvider(range)),
              isEmpty: (history) => history.isEmpty,
              emptyIcon: Icons.local_shipping_rounded,
              emptyMessage: 'لا توجد مشتريات في هذه الفترة',
              dataBuilder: (context, history) {
                final totalPurchases = history.fold<double>(0, (sum, h) => sum + (h['total_amount'] as num).toDouble());

                return Column(
                  children: [
                    ReportMetricGrid(
                      crossAxisCount: 1,
                      childAspectRatio: 4,
                      metrics: [
                        ReportMetricModel(
                          title: 'إجمالي المشتريات للفترة المحددة',
                          value: '${nfInt.format(totalPurchases)} د.ع',
                          icon: Icons.payments_rounded,
                          color: AppColors.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ReportTableCard(
                        title: 'الموردون',
                        columns: const [
                          DataColumn(label: Text('المورد')),
                          DataColumn(label: Text('عدد الفواتير'), numeric: true),
                          DataColumn(label: Text('إجمالي قيمة المشتريات'), numeric: true),
                        ],
                        rows: history.map((h) {
                          final supplierId = h['supplier_id'] as int?;
                          return ReportDrillDownActions.interactiveRow(
                            onSelectChanged: ReportDrillDownActions.rowHandler(
                              context,
                              ref,
                              target: supplierId == null
                                  ? null
                                  : ReportDrillDownTarget(
                                      type: ReportDrillDownEntityType.supplier,
                                      id: supplierId,
                                      label: h['supplier_name'] as String?,
                                    ),
                            ),
                            cells: [
                              DataCell(Row(
                                children: [
                                  const CircleAvatar(radius: 14, backgroundColor: AppColors.warningLight, child: Icon(Icons.person_rounded, size: 16, color: AppColors.warning)),
                                  const SizedBox(width: 12),
                                  Text(h['supplier_name'] as String? ?? 'بدون مورد', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              )),
                              DataCell(Text(h['invoice_count'].toString())),
                              DataCell(Text('${nfInt.format(h['total_amount'] ?? 0)} د.ع', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopCustomersTab extends ConsumerWidget {
  final NumberFormat nfInt;
  const _TopCustomersTab({required this.nfInt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topAsync = ref.watch(reportTopCustomersProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ReportAsyncBody<List<Map<String, dynamic>>>(
        asyncValue: topAsync,
        loadingStyle: ReportLoadingStyle.skeletonChart,
        onRetry: () => ref.invalidate(reportTopCustomersProvider),
        isEmpty: (customers) => customers.isEmpty,
        emptyIcon: Icons.people_outline_rounded,
        emptyMessage: 'لا توجد بيانات عملاء حالياً',
        dataBuilder: (context, customers) {
          final topTen = customers.take(10).toList();
          final chartConfig = ReportChartConfig(
            title: 'أكثر العملاء إنفاقاً',
            type: ReportChartType.bar,
            yAxisFormatter: (v) => nfInt.format(v),
            series: [
              ReportChartSeries(
                id: 'spent',
                label: 'إجمالي الإنفاق',
                color: AppColors.accent,
                points: topTen
                    .map((c) => ReportChartPoint(
                          label: c['name'] as String? ?? '-',
                          value: (c['total_spent'] as num).toDouble(),
                        ))
                    .toList(),
              ),
            ],
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: ReportChartCard(config: chartConfig, showLegend: false)),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: ReportTableCard(
                  title: 'قائمة العملاء',
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('العميل')),
                    DataColumn(label: Text('إجمالي الإنفاق'), numeric: true),
                  ],
                  rows: customers.asMap().entries.map((e) {
                    final i = e.key;
                    final c = e.value;
                    final customerId = c['id'] as int?;
                    return ReportDrillDownActions.interactiveRow(
                      onSelectChanged: ReportDrillDownActions.rowHandler(
                        context,
                        ref,
                        target: customerId == null
                            ? null
                            : ReportDrillDownTarget(
                                type: ReportDrillDownEntityType.customer,
                                id: customerId,
                                label: c['name'] as String?,
                              ),
                      ),
                      cells: [
                        DataCell(Text('${i + 1}')),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (c['phone'] != null)
                              Text(c['phone'] as String, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        )),
                        DataCell(Text('${nfInt.format(c['total_spent'])} د.ع', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DebtReportTab extends ConsumerWidget {
  final NumberFormat nfInt;
  const _DebtReportTab({required this.nfInt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAsync = ref.watch(reportTotalOutstandingProvider);
    final debtorsAsync = ref.watch(reportTopDebtorsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Total Outstanding
          totalAsync.when(
            data: (total) => ReportMetricGrid(
              crossAxisCount: 1,
              childAspectRatio: 4,
              metrics: [
                ReportMetricModel(
                  title: 'إجمالي الديون المستحقة (الذمم المدينة)',
                  value: '${nfInt.format(total)} د.ع',
                  icon: Icons.account_balance_wallet_rounded,
                  color: Colors.red,
                ),
              ],
            ),
            loading: () => const ReportLoadingView(),
            error: (e, _) => ReportErrorView(message: 'خطأ: $e'),
          ),
          
          const SizedBox(height: 24),
          
          // Top Debtors List
          Expanded(
            child: ReportAsyncBody<List<Map<String, dynamic>>>(
              asyncValue: debtorsAsync,
              loadingStyle: ReportLoadingStyle.skeletonTable,
              onRetry: () => ref.invalidate(reportTopDebtorsProvider),
              isEmpty: (debtors) => debtors.isEmpty,
              emptyIcon: Icons.check_circle_outline_rounded,
              emptyMessage: 'لا توجد ديون مستحقة على العملاء حالياً',
              dataBuilder: (context, debtors) => ReportTableCard(
                title: 'قائمة المديونين',
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('رقم الهاتف')),
                  DataColumn(label: Text('الرصيد المستحق'), numeric: true),
                ],
                rows: debtors.asMap().entries.map((e) {
                  final i = e.key;
                  final c = e.value;
                  final customerId = c['id'] as int? ?? c['customer_id'] as int?;
                  return ReportDrillDownActions.interactiveRow(
                    onSelectChanged: ReportDrillDownActions.rowHandler(
                      context,
                      ref,
                      target: customerId == null
                          ? null
                          : ReportDrillDownTarget(
                              type: ReportDrillDownEntityType.customer,
                              id: customerId,
                              label: c['name'] as String?,
                            ),
                    ),
                    cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(c['phone'] as String? ?? '-')),
                      DataCell(Text(
                        '${nfInt.format(c['current_balance'])} د.ع',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayableReportTab extends ConsumerWidget {
  final NumberFormat nfInt;
  const _PayableReportTab({required this.nfInt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalAsync = ref.watch(totalPayableProvider);
    final creditorsAsync = ref.watch(topCreditorsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Total Payable
          totalAsync.when(
            data: (total) => ReportMetricGrid(
              crossAxisCount: 1,
              childAspectRatio: 4,
              metrics: [
                ReportMetricModel(
                  title: 'إجمالي الديون المطلوبة (الذمم الدائنة)',
                  value: '${nfInt.format(total)} د.ع',
                  icon: Icons.payment_rounded,
                  color: AppColors.error,
                ),
              ],
            ),
            loading: () => const ReportLoadingView(),
            error: (e, _) => ReportErrorView(message: 'خطأ: $e'),
          ),
          
          const SizedBox(height: 24),
          
          Expanded(
            child: ReportAsyncBody<List<Map<String, dynamic>>>(
              asyncValue: creditorsAsync,
              loadingStyle: ReportLoadingStyle.skeletonTable,
              onRetry: () => ref.invalidate(topCreditorsProvider),
              isEmpty: (creditors) => creditors.isEmpty,
              emptyIcon: Icons.check_circle_outline_rounded,
              emptyMessage: 'لا توجد ديون لموردين حالياً',
              dataBuilder: (context, creditors) => ReportTableCard(
                title: 'قائمة الموردين (الدائنون)',
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('المورد')),
                  DataColumn(label: Text('رقم الهاتف')),
                  DataColumn(label: Text('الرصيد الدائن المستحق'), numeric: true),
                ],
                rows: creditors.asMap().entries.map((e) {
                  final i = e.key;
                  final c = e.value;
                  final supplierId = c['id'] as int? ?? c['supplier_id'] as int?;
                  return ReportDrillDownActions.interactiveRow(
                    onSelectChanged: ReportDrillDownActions.rowHandler(
                      context,
                      ref,
                      target: supplierId == null
                          ? null
                          : ReportDrillDownTarget(
                              type: ReportDrillDownEntityType.supplier,
                              id: supplierId,
                              label: c['name'] as String?,
                            ),
                    ),
                    cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(c['phone'] as String? ?? '-')),
                      DataCell(Text(
                        '${nfInt.format(c['current_balance'])} د.ع',
                        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
