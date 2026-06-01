// lib/features/returns/screens/return_analytics_dashboard_screen.dart
//
// READ-ONLY analytics dashboard for return_audit_logs.
// Never modifies returns, stock, invoices, or sessions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../models/return_analytics_models.dart';
import '../providers/return_analytics_provider.dart';
import '../utils/return_analytics_date_utils.dart';
import '../../invoices/widgets/invoice_details_dialog.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

class ReturnAnalyticsDashboardScreen extends ConsumerStatefulWidget {
  const ReturnAnalyticsDashboardScreen({super.key});

  @override
  ConsumerState<ReturnAnalyticsDashboardScreen> createState() =>
      _ReturnAnalyticsDashboardScreenState();
}

class _ReturnAnalyticsDashboardScreenState
    extends ConsumerState<ReturnAnalyticsDashboardScreen> {
  static final _fmt = NumberFormat('#,##0.##');
  static final _dateFmt = DateFormat('yyyy/MM/dd HH:mm');
  static final _dayFmt = DateFormat('MM/dd');

  void _applyFilter(ReturnAnalyticsFilter f) {
    ref.read(returnAnalyticsFilterProvider.notifier).state =
        ReturnAnalyticsDateUtils.normalizeFilter(f);
    ref.read(recentActivityProvider.notifier).refresh();
  }

  void _resetFilter() {
    ref.read(returnAnalyticsFilterProvider.notifier).state =
        const ReturnAnalyticsFilter();
    ref.read(recentActivityProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _TopBar(onFilter: _applyFilter, onReset: _resetFilter),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OverviewSection(fmt: _fmt),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          flex: 3,
                          child: _TrendSection(fmt: _fmt, dayFmt: _dayFmt)),
                      const SizedBox(width: 16),
                      const Expanded(
                          flex: 2, child: _SuspiciousSection()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          flex: 3,
                          child: _TopProductsSection(fmt: _fmt)),
                      const SizedBox(width: 16),
                      Expanded(
                          flex: 2,
                          child: _CashierSection(fmt: _fmt)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _RecentActivitySection(
                      dateFmt: _dateFmt, fmt: _fmt),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top filter bar
// ---------------------------------------------------------------------------

class _TopBar extends ConsumerStatefulWidget {
  final void Function(ReturnAnalyticsFilter) onFilter;
  final VoidCallback onReset;
  const _TopBar({required this.onFilter, required this.onReset});

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  static final _df = DateFormat('yyyy/MM/dd');
  DateTime? _from;
  DateTime? _to;
  String? _returnType;
  int? _cashierUserId;
  int? _productId;
  bool _syncedFromProvider = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromProvider());
  }

  void _syncFromProvider() {
    final f = ref.read(returnAnalyticsFilterProvider);
    setState(() {
      _from = f.fromDate;
      _to = f.toDate;
      _returnType = f.returnType;
      _cashierUserId = f.cashierUserId;
      _productId = f.productId;
      _syncedFromProvider = true;
    });
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _apply() {
    widget.onFilter(ReturnAnalyticsFilter(
      fromDate: _from,
      toDate: _to,
      returnType: _returnType,
      cashierUserId: _cashierUserId,
      productId: _productId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(returnAnalyticsFilterProvider, (previous, next) {
      if (!_syncedFromProvider) return;
      if (previous == next) return;
      setState(() {
        _from = next.fromDate;
        _to = next.toDate;
        _returnType = next.returnType;
        _cashierUserId = next.cashierUserId;
        _productId = next.productId;
      });
    });

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.analytics_rounded,
              color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          const Text(
            'تحليلات المرتجعات',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const Spacer(),
          // From date
          _FilterChip(
            label: _from == null ? 'من تاريخ' : _df.format(_from!),
            icon: Icons.calendar_today_rounded,
            active: _from != null,
            onTap: () => _pickDate(true),
          ),
          const SizedBox(width: 8),
          // To date
          _FilterChip(
            label: _to == null ? 'حتى تاريخ' : _df.format(_to!),
            icon: Icons.calendar_month_rounded,
            active: _to != null,
            onTap: () => _pickDate(false),
          ),
          const SizedBox(width: 8),
          // Return type dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
              color: AppColors.surface,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _returnType,
                hint: const Text('نوع المرتجع',
                    style: TextStyle(fontSize: 13, color: AppColors.textHint)),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'full', child: Text('إرجاع كامل')),
                  DropdownMenuItem(
                      value: 'partial', child: Text('إرجاع جزئي')),
                ],
                onChanged: (v) => setState(() => _returnType = v),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _FilterDropdown<int?>(
            label: 'الكاشير',
            value: _cashierUserId,
            items: ref.watch(analyticsCashierFilterOptionsProvider).maybeWhen(
              data: (opts) => [
                const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
                ...opts.map((o) => DropdownMenuItem<int?>(
                      value: o.id,
                      child: Text(o.label, overflow: TextOverflow.ellipsis),
                    )),
              ],
              orElse: () => const [
                DropdownMenuItem<int?>(value: null, child: Text('الكل')),
              ],
            ),
            onChanged: (v) => setState(() => _cashierUserId = v),
          ),
          const SizedBox(width: 8),
          _FilterDropdown<int?>(
            label: 'المنتج',
            value: _productId,
            items: ref.watch(analyticsProductFilterOptionsProvider).maybeWhen(
              data: (opts) => [
                const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
                ...opts.map((o) => DropdownMenuItem<int?>(
                      value: o.id,
                      child: Text(o.label, overflow: TextOverflow.ellipsis),
                    )),
              ],
              orElse: () => const [
                DropdownMenuItem<int?>(value: null, child: Text('الكل')),
              ],
            ),
            onChanged: (v) => setState(() => _productId = v),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _apply,
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('تطبيق'),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              setState(() {
                _from = null;
                _to = null;
                _returnType = null;
                _cashierUserId = null;
                _productId = null;
              });
              widget.onReset();
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'إعادة تعيين',
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}


class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.surface,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.textHint)),
          items: items,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
              color: active ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(8),
          color: active ? AppColors.primarySurface : AppColors.surface,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? AppColors.primary : AppColors.textHint),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: active
                        ? AppColors.primary
                        : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overview cards
// ---------------------------------------------------------------------------

class _OverviewSection extends ConsumerWidget {
  final NumberFormat fmt;
  const _OverviewSection({required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVal = ref.watch(returnOverviewProvider);
    return asyncVal.when(
      loading: () => const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator())),
      error: (e, _) => _ErrorCard('خطأ في تحميل الملخص: $e'),
      data: (ov) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _StatCard(
              label: 'إجمالي المرتجعات',
              value: '${ov.totalCount}',
              sub: fmt.format(ov.totalAmount),
              icon: Icons.assignment_return_rounded,
              color: AppColors.primary),
          _StatCard(
              label: 'اليوم',
              value: '${ov.todayCount}',
              sub: fmt.format(ov.todayAmount),
              icon: Icons.today_rounded,
              color: AppColors.accent),
          _StatCard(
              label: 'هذا الأسبوع',
              value: '${ov.weekCount}',
              sub: fmt.format(ov.weekAmount),
              icon: Icons.date_range_rounded,
              color: AppColors.info),
          _StatCard(
              label: 'هذا الشهر',
              value: '${ov.monthCount}',
              sub: fmt.format(ov.monthAmount),
              icon: Icons.calendar_month_rounded,
              color: AppColors.success),
          _StatCard(
              label: 'إرجاع كامل',
              value: '${ov.fullCount}',
              sub: '',
              icon: Icons.undo_rounded,
              color: AppColors.warning),
          _StatCard(
              label: 'إرجاع جزئي',
              value: '${ov.partialCount}',
              sub: '',
              icon: Icons.remove_circle_outline_rounded,
              color: AppColors.primaryLight),
          _StatCard(
              label: 'بحث ذكي',
              value: '${ov.smartLookupCount}',
              sub: '',
              icon: Icons.manage_search_rounded,
              color: AppColors.info),
          _StatCard(
              label: 'منتجات مرتجعة',
              value: '${ov.uniqueProductsReturned}',
              sub: '',
              icon: Icons.inventory_2_rounded,
              color: const Color(0xFF6A1B9A)),
          _StatCard(
              label: 'كاشيرون نشطون',
              value: '${ov.uniqueCashiers}',
              sub: '',
              icon: Icons.people_rounded,
              color: AppColors.primaryDark),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color)),
          if (sub.isNotEmpty)
            Text(sub,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily trend
// ---------------------------------------------------------------------------

class _TrendSection extends ConsumerWidget {
  final NumberFormat fmt;
  final DateFormat dayFmt;
  const _TrendSection({required this.fmt, required this.dayFmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVal = ref.watch(returnTrendProvider);
    return _SectionCard(
      title: 'اتجاه المرتجعات اليومي',
      icon: Icons.trending_up_rounded,
      child: asyncVal.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorCard('خطأ: $e'),
        data: (points) {
          if (points.isEmpty) {
            return const _EmptyState('لا توجد بيانات للفترة المحددة');
          }
          final maxAmt =
              points.map((p) => p.amount).fold(0.0, (a, b) => a > b ? a : b);
          const maxBarW = 160.0;
          return Column(
            children: [
              // Header row
              const Row(
                children: [
                  SizedBox(
                      width: 56,
                      child: Text('التاريخ',
                          style: _headerStyle)),
                  Expanded(
                      child: Text('العمليات',
                          style: _headerStyle)),
                  SizedBox(
                      width: 80,
                      child: Text('المبلغ',
                          style: _headerStyle,
                          textAlign: TextAlign.end)),
                ],
              ),
              const Divider(),
              ...points.map((p) {
                final barW =
                    maxAmt > 0 ? (p.amount / maxAmt) * maxBarW : 0.0;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: Text(
                          _shortDay(p.day),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              height: 14,
                              width: barW,
                              decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withValues(alpha: 0.7),
                                borderRadius:
                                    BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('${p.count}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          fmt.format(p.amount),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  String _shortDay(String day) {
    try {
      final date = DateTime.parse(day);
      return dayFmt.format(date);
    } catch (_) {
      return day;
    }
  }

  static const _headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary);
}

// ---------------------------------------------------------------------------
// Suspicious indicators
// ---------------------------------------------------------------------------

class _SuspiciousSection extends ConsumerWidget {
  const _SuspiciousSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVal = ref.watch(suspiciousFlagsProvider);
    return _SectionCard(
      title: 'مؤشرات مشبوهة',
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.warning,
      child: asyncVal.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorCard('خطأ: $e'),
        data: (flags) {
          if (flags.isEmpty) {
            return const _EmptyState(
                'لا توجد مؤشرات مشبوهة حالياً',
                icon: Icons.check_circle_outline_rounded);
          }
          return Column(
            children: flags
                .map((f) => _FlagTile(flag: f))
                .toList(),
          );
        },
      ),
    );
  }
}

class _FlagTile extends StatelessWidget {
  final SuspiciousFlag flag;
  const _FlagTile({required this.flag});

  @override
  Widget build(BuildContext context) {
    final (bgColor, iconColor) = switch (flag.severity) {
      SuspiciousSeverity.high => (AppColors.errorLight, AppColors.error),
      SuspiciousSeverity.medium =>
        (AppColors.warningLight, AppColors.warning),
      SuspiciousSeverity.low => (AppColors.infoLight, AppColors.info),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: iconColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(flag.title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: iconColor)),
                const SizedBox(height: 2),
                Text(flag.description,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top returned products
// ---------------------------------------------------------------------------

class _TopProductsSection extends ConsumerWidget {
  final NumberFormat fmt;
  const _TopProductsSection({required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVal = ref.watch(topReturnedProductsProvider);
    return _SectionCard(
      title: 'أكثر المنتجات إرجاعاً',
      icon: Icons.inventory_2_rounded,
      child: asyncVal.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorCard('خطأ: $e'),
        data: (products) {
          if (products.isEmpty) {
            return const _EmptyState('لا توجد بيانات');
          }
          final maxAmt = products
              .map((p) => p.totalAmount)
              .fold(0.0, (a, b) => a > b ? a : b);
          return Column(
            children: [
              const _RowHeader(
                  cols: ['المنتج', 'الكمية', 'مرات', 'المبلغ']),
              const Divider(),
              ...products.asMap().entries.map((e) {
                final i = e.key;
                final p = e.value;
                final ratio = maxAmt > 0 ? p.totalAmount / maxAmt : 0.0;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(p.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(height: 2),
                            FractionallySizedBox(
                              widthFactor: ratio,
                              alignment: Alignment.centerRight,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.accent
                                      .withValues(alpha: 0.7),
                                  borderRadius:
                                      BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                          width: 44,
                          child: Text(
                              fmt.format(p.totalQuantity),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11))),
                      SizedBox(
                          width: 36,
                          child: Text('${p.returnCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary))),
                      SizedBox(
                          width: 64,
                          child: Text(
                              fmt.format(p.totalAmount),
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary))),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cashier analytics
// ---------------------------------------------------------------------------

class _CashierSection extends ConsumerWidget {
  final NumberFormat fmt;
  const _CashierSection({required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVal = ref.watch(cashierReturnStatsProvider);
    return _SectionCard(
      title: 'نشاط الكاشيرين',
      icon: Icons.people_rounded,
      child: asyncVal.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorCard('خطأ: $e'),
        data: (stats) {
          if (stats.isEmpty) {
            return const _EmptyState('لا توجد بيانات');
          }
          return Column(
            children: [
              const _RowHeader(
                  cols: ['الكاشير', 'مرتجعات', 'كامل', 'جزئي', 'المبلغ']),
              const Divider(),
              ...stats.map((s) => Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(s.cashierName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ),
                        _Cell('${s.totalReturns}',
                            width: 44, bold: true),
                        _Cell('${s.fullReturns}',
                            width: 36,
                            color: AppColors.warning),
                        _Cell('${s.partialReturns}',
                            width: 36,
                            color: AppColors.info),
                        _Cell(fmt.format(s.totalAmount),
                            width: 70,
                            color: AppColors.primary,
                            bold: true),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent activity
// ---------------------------------------------------------------------------

class _RecentActivitySection extends ConsumerWidget {
  final DateFormat dateFmt;
  final NumberFormat fmt;
  const _RecentActivitySection(
      {required this.dateFmt, required this.fmt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(recentActivityProvider);
    const pageSize = 50;
    final totalPages =
        (state.totalCount / pageSize).ceil().clamp(1, 9999);

    return _SectionCard(
      title: 'سجل النشاط الأخير  (${state.totalCount} سجل)',
      icon: Icons.history_rounded,
      trailing: state.isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: () =>
                  ref.read(recentActivityProvider.notifier).refresh(),
              tooltip: 'تحديث',
            ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            color: AppColors.surfaceVariant,
            child: const Row(
              children: [
                _TH('التاريخ/الوقت', flex: 3),
                _TH('الكاشير', flex: 2),
                _TH('النوع', flex: 2),
                _TH('الفاتورة', flex: 2),
                _TH('المنتج', flex: 3),
                _TH('الكمية', flex: 1),
                _TH('المبلغ', flex: 2),
                _TH('الملاحظة', flex: 3),
              ],
            ),
          ),
          if (state.rows.isEmpty && !state.isLoading && state.hasLoadedOnce)
            const _EmptyState('لا توجد سجلات للمعايير المحددة')
          else
            ...state.rows.map(
              (row) => InkWell(
                onTap: row.invoiceId != null
                    ? () => showDialog(
                          context: context,
                          builder: (_) => InvoiceDetailsDialog(
                              invoiceId: row.invoiceId!),
                        )
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                            color: AppColors.divider)),
                  ),
                  child: Row(
                    children: [
                      _TD(dateFmt.format(row.createdAt),
                          flex: 3),
                      _TD(row.cashierName, flex: 2),
                      Expanded(
                        flex: 2,
                        child: _ReturnTypeBadge(
                            row.returnType),
                      ),
                      _TD(
                          row.invoiceId != null
                              ? '#${row.invoiceId}'
                              : '—',
                          flex: 2,
                          link: row.invoiceId != null),
                      _TD(row.productName ?? '—', flex: 3),
                      _TD(
                          fmt.format(row.returnedQuantity),
                          flex: 1),
                      _TD(
                          fmt.format(row.returnedAmount),
                          flex: 2,
                          color: AppColors.primary,
                          bold: true),
                      _TD(
                          row.returnNote ??
                              row.returnReason ??
                              '—',
                          flex: 3,
                          muted: true),
                    ],
                  ),
                ),
              ),
            ),
          // Pagination
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    onPressed: state.page > 0
                        ? () => ref
                            .read(recentActivityProvider.notifier)
                            .loadPage(state.page - 1)
                        : null,
                  ),
                  Text(
                    'صفحة ${state.page + 1} من $totalPages',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    onPressed: state.page < totalPages - 1
                        ? () => ref
                            .read(recentActivityProvider.notifier)
                            .loadPage(state.page + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReturnTypeBadge extends StatelessWidget {
  final String type;
  const _ReturnTypeBadge(this.type);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      'full' => ('كامل', AppColors.warning),
      'partial' => ('جزئي', AppColors.info),
      _ => (type, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon,
                    color: iconColor ?? AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _RowHeader extends StatelessWidget {
  final List<String> cols;
  const _RowHeader({required this.cols});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: cols
          .map((c) => Expanded(
                child: Text(c,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ))
          .toList(),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final double width;
  final Color? color;
  final bool bold;

  const _Cell(this.text,
      {required this.width, this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  final int flex;
  const _TH(this.text, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary)),
    );
  }
}

class _TD extends StatelessWidget {
  final String text;
  final int flex;
  final Color? color;
  final bool bold;
  final bool muted;
  final bool link;

  const _TD(this.text,
      {required this.flex,
      this.color,
      this.bold = false,
      this.muted = false,
      this.link = false});

  @override
  Widget build(BuildContext context) {
    Color effectiveColor;
    if (link) {
      effectiveColor = AppColors.primary;
    } else if (muted) {
      effectiveColor = AppColors.textHint;
    } else {
      effectiveColor = color ?? AppColors.textPrimary;
    }
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: effectiveColor,
          decoration: link ? TextDecoration.underline : null,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const _EmptyState(this.message,
      {this.icon = Icons.inbox_rounded});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textHint, size: 32),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message,
          style: const TextStyle(
              color: AppColors.error, fontSize: 12)),
    );
  }
}