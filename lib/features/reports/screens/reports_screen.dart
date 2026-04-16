// lib/features/reports/screens/reports_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/stat_card.dart';
import '../providers/reports_provider.dart';
import '../../suppliers/providers/supplier_accounts_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );
  DateTimeRange _purchasesRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now(),
  );

  final _nf = NumberFormat('#,##0.##');
  final _nfInt = NumberFormat('#,##0');
  final _df = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
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
              _DailyReportTab(selectedDate: _selectedDate, nf: _nf, nfInt: _nfInt, df: _df, onDateChange: (d) => setState(() => _selectedDate = d)),
              _MonthlySalesTab(year: _selectedYear, nfInt: _nfInt, onYearChange: (y) => setState(() => _selectedYear = y)),
              _TopProductsTab(range: _selectedRange, nf: _nf, nfInt: _nfInt, onRangeChange: (r) => setState(() => _selectedRange = r)),
              _InventoryValueTab(nf: _nf, nfInt: _nfInt),
              _PurchaseHistoryTab(range: _purchasesRange, nfInt: _nfInt, onRangeChange: (r) => setState(() => _purchasesRange = r)),
              _TopCustomersTab(nfInt: _nfInt),
              _DebtReportTab(nfInt: _nfInt),
              _PayableReportTab(nfInt: _nfInt),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyReportTab extends ConsumerWidget {
  final DateTime selectedDate;
  final NumberFormat nf;
  final NumberFormat nfInt;
  final DateFormat df;
  final ValueChanged<DateTime> onDateChange;

  const _DailyReportTab({required this.selectedDate, required this.nf, required this.nfInt, required this.df, required this.onDateChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyAsync = ref.watch(reportDailySalesProvider(selectedDate));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Date selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => onDateChange(selectedDate.subtract(const Duration(days: 1)))),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (picked != null) onDateChange(picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(df.format(selectedDate), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: selectedDate.day == DateTime.now().day ? null : () => onDateChange(selectedDate.add(const Duration(days: 1)))),
            ],
          ),
          const SizedBox(height: 24),
          dailyAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                const SizedBox(height: 12),
                Text('خطأ: $e', style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                  onPressed: () => ref.invalidate(reportDailySalesProvider(selectedDate)),
                ),
              ]),
            ),
            data: (data) {
              final total = (data['total'] as num?)?.toDouble() ?? 0;
              final count = (data['count'] as num?)?.toInt() ?? 0;
              final profit = (data['profit'] as num?)?.toDouble() ?? 0;
              final cash = (data['cash'] as num?)?.toDouble() ?? 0;
              final card = (data['card'] as num?)?.toDouble() ?? 0;
              return Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.2,
                  children: [
                    StatCard(title: 'إجمالي المبيعات', value: '${nfInt.format(total)} د.ع', icon: Icons.point_of_sale_rounded, color: AppColors.primary),
                    StatCard(title: 'عدد الفواتير', value: '$count فاتورة', icon: Icons.receipt_long_rounded, color: AppColors.info),
                    StatCard(title: 'الربح المتوقع', value: '${nfInt.format(profit)} د.ع', icon: Icons.trending_up_rounded, color: AppColors.success),
                    StatCard(title: 'مبيعات نقدي', value: '${nfInt.format(cash)} د.ع', icon: Icons.money_rounded, color: AppColors.warning),
                    StatCard(title: 'مبيعات بطاقة', value: '${nfInt.format(card)} د.ع', icon: Icons.credit_card_rounded, color: AppColors.accent),
                    StatCard(title: 'متوسط الفاتورة', value: count > 0 ? '${nfInt.format(total / count)} د.ع' : '-', icon: Icons.calculate_rounded, color: AppColors.primary),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TopProductsTab extends ConsumerWidget {
  final DateTimeRange range;
  final NumberFormat nf;
  final NumberFormat nfInt;
  final ValueChanged<DateTimeRange> onRangeChange;
  const _TopProductsTab({required this.range, required this.nf, required this.nfInt, required this.onRangeChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topAsync = ref.watch(reportTopProductsProvider(range));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: const Text('عرض الفترة'),
                onPressed: () async {
                  final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: range);
                  if (picked != null) onRangeChange(picked);
                },
              ),
              const SizedBox(width: 12),
              Text('من ${DateFormat('yyyy/MM/dd').format(range.start)} إلى ${DateFormat('yyyy/MM/dd').format(range.end)}', style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: topAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text('خطأ: $e', style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                    onPressed: () => ref.invalidate(reportTopProductsProvider(range)),
                  ),
                ]),
              ),
              data: (products) => products.isEmpty
                  ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.bar_chart_rounded, size: 64, color: AppColors.textHint),
                      SizedBox(height: 16),
                      Text('لا توجد مبيعات في هذه الفترة', style: TextStyle(color: AppColors.textHint)),
                    ]))
                  : Card(
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 16,
                          columns: const [
                            DataColumn(label: Text('#')),
                            DataColumn(label: Text('المنتج')),
                            DataColumn(label: Text('الكمية المباعة'), numeric: true),
                            DataColumn(label: Text('الإيراد'), numeric: true),
                          ],
                          rows: products.asMap().entries.map((e) {
                            final i = e.key;
                            final p = e.value;
                            return DataRow(cells: [
                              DataCell(CircleAvatar(radius: 14, backgroundColor: i < 3 ? AppColors.accent : AppColors.primary.withValues(alpha: 0.1), child: Text('${i + 1}', style: TextStyle(color: i < 3 ? Colors.white : AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)))),
                              DataCell(Text(p['name'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text(nf.format(p['total_qty'] ?? 0))),
                              DataCell(Text('${nfInt.format(p['total_revenue'] ?? 0)} د.ع', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary))),
                            ]);
                          }).toList(),
                        ),
                      ),
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
  final int year;
  final NumberFormat nfInt;
  final ValueChanged<int> onYearChange;
  const _MonthlySalesTab({required this.year, required this.nfInt, required this.onYearChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthlyAsync = ref.watch(reportMonthlySalesProvider(year));
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => onYearChange(year - 1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text('سنة $year', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: year >= DateTime.now().year ? null : () => onYearChange(year + 1)),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: monthlyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text('خطأ: $e', style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                    onPressed: () => ref.invalidate(reportMonthlySalesProvider(year)),
                  ),
                ]),
              ),
              data: (months) {
                if (months.isEmpty) {
                  return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.calendar_month_rounded, size: 64, color: AppColors.textHint),
                    SizedBox(height: 16),
                    Text('لا توجد مبيعات في هذه السنة', style: TextStyle(color: AppColors.textHint)),
                  ]));
                }

                // Fill missing months with 0
                final fullMonths = List.generate(12, (i) {
                  final mStr = (i + 1).toString().padLeft(2, '0');
                  final existing = months.cast<Map<String,dynamic>?>().firstWhere((m) => m?['month'] == mStr, orElse: () => null);
                  return existing ?? {'month': mStr, 'invoice_count': 0, 'total_revenue': 0.0, 'total_profit': 0.0};
                });

                final maxRevenue = fullMonths.fold<double>(0, (m, data) => (data['total_revenue'] as num).toDouble() > m ? (data['total_revenue'] as num).toDouble() : m);

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chart
                    Expanded(
                      flex: 2,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('المبيعات والأرباح الشهرية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 32),
                              Expanded(
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: maxRevenue * 1.2,
                                    barTouchData: BarTouchData(enabled: false),
                                    titlesData: FlTitlesData(
                                      show: true,
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (value, meta) => Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text(value.toInt().toString(), style: const TextStyle(fontSize: 12)),
                                          ),
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 60,
                                          getTitlesWidget: (value, meta) => Text(nfInt.format(value), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                        ),
                                      ),
                                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    ),
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: false,
                                      horizontalInterval: maxRevenue > 0 ? maxRevenue / 4 : 1000,
                                      getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.2), strokeWidth: 1),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    barGroups: fullMonths.asMap().entries.map((e) {
                                      final i = e.key;
                                      final data = e.value;
                                      final rev = (data['total_revenue'] as num).toDouble();
                                      final pro = (data['total_profit'] as num).toDouble();
                                      return BarChartGroupData(
                                        x: i + 1,
                                        barRods: [
                                          BarChartRodData(toY: rev, color: AppColors.primary, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                                          BarChartRodData(toY: pro, color: AppColors.success, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(width: 12, height: 12, color: AppColors.primary), const SizedBox(width: 4), const Text('الإيراد'),
                                  const SizedBox(width: 24),
                                  Container(width: 12, height: 12, color: AppColors.success), const SizedBox(width: 4), const Text('الربح'),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Table
                    Expanded(
                      flex: 1,
                      child: Card(
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 16,
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
            child: invAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text('خطأ: $e', style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                    onPressed: () => ref.invalidate(reportInventoryValueProvider),
                  ),
                ]),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.warehouse_rounded, size: 64, color: AppColors.textHint),
                    SizedBox(height: 16),
                    Text('لا يوجد مخزون مقيم حالياً', style: TextStyle(color: AppColors.textHint)),
                  ]));
                }

                final totalValue = products.fold<double>(0, (sum, p) => sum + (p['total_value'] as num).toDouble());

                return Column(
                  children: [
                    StatCard(
                      title: 'إجمالي قيمة المخزون الحالية', 
                      value: '${nfInt.format(totalValue)} د.ع', 
                      icon: Icons.attach_money_rounded, 
                      color: AppColors.success,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 16,
                            columns: const [
                              DataColumn(label: Text('المنتج')),
                              DataColumn(label: Text('الباركود')),
                              DataColumn(label: Text('الكمية الحالية'), numeric: true),
                              DataColumn(label: Text('متوسط التكلفة'), numeric: true),
                              DataColumn(label: Text('إجمالي القيمة'), numeric: true),
                            ],
                            rows: products.map((p) {
                              return DataRow(cells: [
                                DataCell(Text(p['product_name'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text(p['barcode'] as String? ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                                DataCell(Text(nf.format(p['current_stock'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text('${nf.format(p['cost_price'] ?? 0)} د.ع')),
                                DataCell(Text('${nfInt.format(p['total_value'] ?? 0)} د.ع', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success))),
                              ]);
                            }).toList(),
                          ),
                        ),
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
  final DateTimeRange range;
  final NumberFormat nfInt;
  final ValueChanged<DateTimeRange> onRangeChange;

  const _PurchaseHistoryTab({required this.range, required this.nfInt, required this.onRangeChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchAsync = ref.watch(reportPurchasesProvider(range));
    final df = DateFormat('yyyy/MM/dd');
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: const Text('عرض الفترة'),
                onPressed: () async {
                  final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: range);
                  if (picked != null) onRangeChange(picked);
                },
              ),
              const SizedBox(width: 12),
              Text('من ${df.format(range.start)} إلى ${df.format(range.end)}', style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: purchAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text('خطأ: $e', style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                    onPressed: () => ref.invalidate(reportPurchasesProvider(range)),
                  ),
                ]),
              ),
              data: (history) {
                if (history.isEmpty) {
                  return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.local_shipping_rounded, size: 64, color: AppColors.textHint),
                    SizedBox(height: 16),
                    Text('لا توجد مشتريات في هذه الفترة', style: TextStyle(color: AppColors.textHint)),
                  ]));
                }
                
                final totalPurchases = history.fold<double>(0, (sum, h) => sum + (h['total_amount'] as num).toDouble());
                
                return Column(
                  children: [
                    Row(
                      children: [
                        StatCard(
                          title: 'إجمالي المشتريات للفترة المحددة', 
                          value: '${nfInt.format(totalPurchases)} د.ع', 
                          icon: Icons.payments_rounded, 
                          color: AppColors.warning,
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Card(
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 16,
                            columns: const [
                              DataColumn(label: Text('المورد')),
                              DataColumn(label: Text('عدد الفواتير'), numeric: true),
                              DataColumn(label: Text('إجمالي قيمة المشتريات'), numeric: true),
                            ],
                            rows: history.map((h) {
                              return DataRow(cells: [
                                DataCell(Row(
                                  children: [
                                    const CircleAvatar(radius: 14, backgroundColor: AppColors.warningLight, child: Icon(Icons.person_rounded, size: 16, color: AppColors.warning)),
                                    const SizedBox(width: 12),
                                    Text(h['supplier_name'] as String? ?? 'بدون مورد', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ],
                                )),
                                DataCell(Text(h['invoice_count'].toString())),
                                DataCell(Text('${nfInt.format(h['total_amount'] ?? 0)} د.ع', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning))),
                              ]);
                            }).toList(),
                          ),
                        ),
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
      child: topAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text('خطأ: $e', style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
              onPressed: () => ref.invalidate(reportTopCustomersProvider),
            ),
          ]),
        ),
        data: (customers) {
          if (customers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline_rounded, size: 64, color: AppColors.textHint),
                  SizedBox(height: 16),
                  Text('لا توجد بيانات عملاء حالياً', style: TextStyle(color: AppColors.textHint)),
                ],
              ),
            );
          }

          final maxSpent = customers.fold<double>(0, (maxVal, c) {
            final spent = (c['total_spent'] as num).toDouble();
            return spent > maxVal ? spent : maxVal;
          });

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chart
              Expanded(
                flex: 2,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('أكثر العملاء إنفاقاً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 32),
                        Expanded(
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: maxSpent * 1.2,
                              barTouchData: BarTouchData(enabled: true),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt() - 1;
                                      if (index >= 0 && index < customers.length) {
                                        final name = customers[index]['name'] as String;
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            name.length > 8 ? '${name.substring(0, 8)}...' : name,
                                            style: const TextStyle(fontSize: 10),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      }
                                      return const Text('');
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 60,
                                    getTitlesWidget: (value, meta) => Text(
                                      nfInt.format(value),
                                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                    ),
                                  ),
                                ),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: maxSpent > 0 ? maxSpent / 4 : 10000,
                                getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withValues(alpha: 0.1), strokeWidth: 1),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: customers.asMap().entries.take(10).map((e) {
                                final i = e.key;
                                final data = e.value;
                                final spent = (data['total_spent'] as num).toDouble();
                                return BarChartGroupData(
                                  x: i + 1,
                                  barRods: [
                                    BarChartRodData(
                                      toY: spent,
                                      color: AppColors.accent,
                                      width: 20,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Table
              Expanded(
                flex: 1,
                child: Card(
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 16,
                      columns: const [
                        DataColumn(label: Text('#')),
                        DataColumn(label: Text('العميل')),
                        DataColumn(label: Text('إجمالي الإنفاق'), numeric: true),
                      ],
                      rows: customers.asMap().entries.map((e) {
                        final i = e.key;
                        final c = e.value;
                        return DataRow(cells: [
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
                        ]);
                      }).toList(),
                    ),
                  ),
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
            data: (total) => Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: 'إجمالي الديون المستحقة (الذمم المدينة)',
                    value: '${nfInt.format(total)} د.ع',
                    icon: Icons.account_balance_wallet_rounded,
                    color: Colors.red,
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('خطأ: $e', style: const TextStyle(color: Colors.red)),
          ),
          
          const SizedBox(height: 24),
          
          // Top Debtors List
          Expanded(
            child: debtorsAsync.when(
              data: (debtors) {
                if (debtors.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.green),
                        SizedBox(height: 16),
                        Text('لا توجد ديون مستحقة على العملاء حالياً', style: TextStyle(color: Colors.green, fontSize: 16)),
                      ],
                    ),
                  );
                }
                
                return Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'قائمة المديونين',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 16,
                            columns: const [
                              DataColumn(label: Text('#')),
                              DataColumn(label: Text('العميل')),
                              DataColumn(label: Text('رقم الهاتف')),
                              DataColumn(label: Text('الرصيد المستحق'), numeric: true),
                            ],
                            rows: debtors.asMap().entries.map((e) {
                              final i = e.key;
                              final c = e.value;
                              return DataRow(cells: [
                                DataCell(Text('${i + 1}')),
                                DataCell(Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(c['phone'] as String? ?? '-')),
                                DataCell(Text(
                                  '${nfInt.format(c['current_balance'])} د.ع',
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e', style: const TextStyle(color: Colors.red))),
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
            data: (total) => Row(
              children: [
                Expanded(
                  child: StatCard(
                    title: 'إجمالي الديون المطلوبة (الذمم الدائنة)',
                    value: '${nfInt.format(total)} د.ع',
                    icon: Icons.payment_rounded,
                    color: AppColors.error,
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('خطأ: $e', style: const TextStyle(color: AppColors.error)),
          ),
          
          const SizedBox(height: 24),
          
          // Top Creditors List
          Expanded(
            child: creditorsAsync.when(
              data: (creditors) {
                if (creditors.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.success),
                        SizedBox(height: 16),
                        Text('لا توجد ديون لموردين حالياً', style: TextStyle(color: AppColors.success, fontSize: 16)),
                      ],
                    ),
                  );
                }
                
                return Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'قائمة الموردين (الدائنون)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          child: DataTable(
                            columnSpacing: 16,
                            columns: const [
                              DataColumn(label: Text('#')),
                              DataColumn(label: Text('المورد')),
                              DataColumn(label: Text('رقم الهاتف')),
                              DataColumn(label: Text('الرصيد الدائن المستحق'), numeric: true),
                            ],
                            rows: creditors.asMap().entries.map((e) {
                              final i = e.key;
                              final c = e.value;
                              return DataRow(cells: [
                                DataCell(Text('${i + 1}')),
                                DataCell(Text(c['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(c['phone'] as String? ?? '-')),
                                DataCell(Text(
                                  '${nfInt.format(c['current_balance'])} د.ع',
                                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e', style: const TextStyle(color: AppColors.error))),
            ),
          ),
        ],
      ),
    );
  }
}
