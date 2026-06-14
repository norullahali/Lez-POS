import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../reports/core/models/report_date_preset.dart';
import '../../reports/core/models/report_filter_model.dart';
import '../../reports/core/providers/report_permissions.dart';
import '../../reports/core/services/report_drill_down_service.dart';
import '../../reports/core/models/report_drill_down.dart';
import '../../reports/core/models/report_metric_model.dart';
import '../../reports/core/widgets/report_async_body.dart';
import '../../reports/core/widgets/report_filter_bar.dart';
import '../../reports/core/widgets/report_table_widgets.dart';
import '../../reports/modules/shared/analytics_formatters.dart';
import '../../reports/modules/shared/analytics_permission_gate.dart';
import '../models/cash_ledger_event.dart';
import '../models/cash_ledger_event_type.dart';
import '../models/cash_ledger_summary.dart';
import '../providers/cash_ledger_filter_provider.dart';
import '../providers/cash_ledger_providers.dart';
import '../widgets/cash_ledger_export_helper.dart';

/// Financial Management Center — Cash Ledger v1 (read-only derived ledger).
class CashLedgerScreen extends ConsumerStatefulWidget {
  const CashLedgerScreen({super.key});

  @override
  ConsumerState<CashLedgerScreen> createState() => _CashLedgerScreenState();
}

class _CashLedgerScreenState extends ConsumerState<CashLedgerScreen> {
  final _searchCtrl = TextEditingController();
  final _ledgerVScrollCtrl = ScrollController(); // FORENSIC TEMP
  final _df = DateFormat('yyyy/MM/dd HH:mm');

  @override
  void initState() {
    super.initState();
    // FORENSIC TEMP: apply "This Year" filter for runtime capture
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onDateFilterChanged(
        const ReportFilterModel(preset: ReportDatePreset.thisYear),
      );
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _ledgerVScrollCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(cashLedgerSummaryProvider);
    ref.invalidate(cashLedgerEntriesProvider);
  }

  void _onDateFilterChanged(ReportFilterModel filter) {
    final range = filter.resolveRange();
    final sqlStart =
        DateTime(range.start.year, range.start.month, range.start.day);
    final sqlEnd = DateTime(range.end.year, range.end.month, range.end.day)
        .add(const Duration(days: 1));
    debugPrint(
      '[CashLedger] preset=${filter.preset.labelAr} '
      'rangeStart=${range.start.toIso8601String().split('T').first} '
      'rangeEnd=${range.end.toIso8601String().split('T').first} '
      'sqlStart=$sqlStart sqlEndExclusive=$sqlEnd',
    );
    ref.read(cashLedgerFilterProvider.notifier).setDateFilter(filter);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(cashLedgerSummaryProvider, (previous, next) {
      next.whenData((summary) {
        debugPrint(
          '[CashLedger] preset=${ref.read(cashLedgerFilterProvider).dateFilter.preset.labelAr} '
          'matchingRows=${summary.transactionCount} '
          'inflow=${summary.totalInflow} outflow=${summary.totalOutflow}',
        );
      });
    });

    return AnalyticsPermissionGate(
      requiresFinancial: true,
      requiresInventory: false,
      requiresExecutive: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 16),
            SizedBox(height: 88, child: _buildSummarySection()),
            const SizedBox(height: 12),
            _buildFilters(),
            const SizedBox(height: 12),
            Expanded(child: _buildLedgerTable()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الماليات',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      )),
              const SizedBox(height: 2),
              Text('دفتر النقدية — سجل مشتق (قراءة فقط)',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
        Chip(
          avatar: Icon(Icons.lock_outline, size: 16, color: AppColors.info),
          label: const Text('قراءة فقط'),
          backgroundColor: AppColors.info.withValues(alpha: 0.08),
        ),
      ],
    );
  }

  Widget _buildSummarySection() {
    final summaryAsync = ref.watch(cashLedgerSummaryProvider);
    return ReportAsyncBody<CashLedgerSummary>(
      asyncValue: summaryAsync,
      onRetry: _refresh,
      loadingStyle: ReportLoadingStyle.spinner,
      dataBuilder: (_, summary) {
        final metrics = [
          ReportMetricModel(
            title: 'النقد الوارد',
            value: AnalyticsFormatters.money(summary.totalInflow),
            icon: Icons.arrow_downward_rounded,
            color: AppColors.success,
          ),
          ReportMetricModel(
            title: 'النقد الصادر',
            value: AnalyticsFormatters.money(summary.totalOutflow),
            icon: Icons.arrow_upward_rounded,
            color: AppColors.error,
          ),
          ReportMetricModel(
            title: 'صافي التدفق',
            value: AnalyticsFormatters.money(summary.netCashFlow),
            icon: Icons.sync_alt_rounded,
            color: AppColors.primary,
          ),
          ReportMetricModel(
            title: 'عدد الحركات',
            value: '${summary.transactionCount}',
            icon: Icons.receipt_long_rounded,
            color: AppColors.info,
          ),
        ];
        return Row(
          children: [
            for (var i = 0; i < metrics.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 6,
                    right: i == metrics.length - 1 ? 0 : 6,
                  ),
                  child: _CashLedgerKpiTile(metric: metrics[i]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilters() {
    final filter = ref.watch(cashLedgerFilterProvider);
    final canExport = ref.watch(canExportReportsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportFilterBar(
          filter: filter.dateFilter,
          onFilterChanged: _onDateFilterChanged,
          onRefresh: _refresh,
          onExport: canExport
              ? () => CashLedgerExportHelper.exportCsv(context, ref)
              : null,
          showExport: true,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<CashLedgerEventType?>(
                  initialValue: filter.eventType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الحركة',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('الكل')),
                    ...CashLedgerEventType.values.map(
                      (t) => DropdownMenuItem(value: t, child: Text(t.labelAr)),
                    ),
                  ],
                  onChanged: (v) =>
                      ref.read(cashLedgerFilterProvider.notifier).setEventType(v),
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'بحث',
                    hintText: 'وصف أو رقم مرجع',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => ref
                          .read(cashLedgerFilterProvider.notifier)
                          .setSearchQuery(_searchCtrl.text.trim()),
                    ),
                  ),
                  onSubmitted: (v) => ref
                      .read(cashLedgerFilterProvider.notifier)
                      .setSearchQuery(v.trim()),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _searchCtrl.clear();
                  ref.read(cashLedgerFilterProvider.notifier).resetFilters();
                  _refresh();
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('إعادة تعيين'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLedgerTable() {
    final pageAsync = ref.watch(cashLedgerEntriesProvider);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: SizedBox.expand(
        child: ReportAsyncBody<CashLedgerPage>(
          asyncValue: pageAsync,
          onRetry: _refresh,
          loadingStyle: ReportLoadingStyle.spinner,
          dataBuilder: (_, page) {
            final columns = const [
              DataColumn(label: Text('التاريخ')),
              DataColumn(label: Text('النوع')),
              DataColumn(label: Text('المرجع')),
              DataColumn(label: Text('الوصف')),
              DataColumn(label: Text('وارد'), numeric: true),
              DataColumn(label: Text('صادر'), numeric: true),
              DataColumn(label: Text('الرصيد'), numeric: true),
            ];

            final rows =
                page.entries.map((e) => _buildRow(context, ref, e)).toList();

            // FORENSIC TEMP
            debugPrint(
              '[CashLedger FORENSIC] page.totalCount=${page.totalCount} '
              'page.entries.length=${page.entries.length} rows.length=${rows.length}',
            );
            for (var i = 0; i < page.entries.length && i < 10; i++) {
              final e = page.entries[i];
              debugPrint(
                '[CashLedger FORENSIC] row[$i] ledger_id=${e.id} eventType=${e.eventType.code}',
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReportTableHeader(
                  title: 'حركات دفتر النقدية',
                  subtitle:
                      '${page.totalCount} حركة — صفحة ${page.page + 1} من ${page.totalPages == 0 ? 1 : page.totalPages}',
                ),
                const Divider(height: 1),
                Expanded(
                  child: page.entries.isEmpty
                      ? const Center(
                          child: ReportTableEmptyState(
                            message:
                                'لا توجد حركات نقدية في الفترة المحددة',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            // FORENSIC TEMP
                            debugPrint(
                              '[CashLedger FORENSIC] constraints.maxWidth=${constraints.maxWidth} '
                              'constraints.maxHeight=${constraints.maxHeight}',
                            );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_ledgerVScrollCtrl.hasClients) {
                                final p = _ledgerVScrollCtrl.position;
                                debugPrint(
                                  '[CashLedger FORENSIC] scroll.pixels=${p.pixels} '
                                  'scroll.maxScrollExtent=${p.maxScrollExtent} '
                                  'scroll.viewportDimension=${p.viewportDimension}',
                                );
                              } else {
                                debugPrint(
                                  '[CashLedger FORENSIC] scroll controller has no clients',
                                );
                              }
                            });
                            return Scrollbar(
                              thumbVisibility: true,
                              controller: _ledgerVScrollCtrl,
                              child: SingleChildScrollView(
                                controller: _ledgerVScrollCtrl,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: DataTable(
                                      columnSpacing: 16,
                                      headingRowHeight: 44,
                                      dataRowMinHeight: 44,
                                      dataRowMaxHeight: 72,
                                      columns: columns,
                                      rows: rows,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                _PaginationBar(
                  page: page,
                  onPageChanged: (p) => ref
                      .read(cashLedgerFilterProvider.notifier)
                      .setPage(p),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  DataRow _buildRow(BuildContext context, WidgetRef ref, CashLedgerEvent e) {
    final refLabel = '${e.referenceType} #${e.referenceId}';
    return DataRow(
      onSelectChanged: (_) => _openDrillDown(context, ref, e),
      cells: [
        DataCell(Text(_df.format(e.timestamp))),
        DataCell(Text(e.eventType.labelAr)),
        DataCell(Text(refLabel, style: const TextStyle(fontSize: 12))),
        DataCell(Text(e.description, maxLines: 2, overflow: TextOverflow.ellipsis)),
        DataCell(Text(
          e.isInflow ? AnalyticsFormatters.money(e.amount) : AnalyticsFormatters.empty,
          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
        )),
        DataCell(Text(
          e.isInflow ? AnalyticsFormatters.empty : AnalyticsFormatters.money(e.amount),
          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
        )),
        DataCell(Text(
          e.runningBalance != null
              ? AnalyticsFormatters.money(e.runningBalance!)
              : AnalyticsFormatters.empty,
          style: const TextStyle(fontWeight: FontWeight.w700),
        )),
      ],
    );
  }

  Future<void> _openDrillDown(
    BuildContext context,
    WidgetRef ref,
    CashLedgerEvent e,
  ) async {
    switch (e.eventType) {
      case CashLedgerEventType.saleCash:
      case CashLedgerEventType.returnRefund:
        final invId = e.invoiceId ?? e.referenceId;
        await ReportDrillDownService.open(
          context,
          ref,
          ReportDrillDownTarget(type: ReportDrillDownEntityType.invoice, id: invId),
        );
      case CashLedgerEventType.customerPayment:
        if (e.customerId != null && e.customerId! > 1) {
          await ReportDrillDownService.open(
            context,
            ref,
            ReportDrillDownTarget(
              type: ReportDrillDownEntityType.customer,
              id: e.customerId!,
            ),
          );
        }
      case CashLedgerEventType.purchaseCash:
      case CashLedgerEventType.supplierPayment:
        if (e.supplierId != null) {
          ReportDrillDownService.open(
            context,
            ref,
            ReportDrillDownTarget(
              type: ReportDrillDownEntityType.supplier,
              id: e.supplierId!,
            ),
          );
        }
    }
  }
}

class _CashLedgerKpiTile extends StatelessWidget {
  const _CashLedgerKpiTile({required this.metric});

  final ReportMetricModel metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: metric.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(metric.icon, color: metric.color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    metric.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.page, required this.onPageChanged});

  final CashLedgerPage page;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'السابق',
            onPressed: page.hasPreviousPage ? () => onPageChanged(page.page - 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Text('صفحة ${page.page + 1} / ${page.totalPages == 0 ? 1 : page.totalPages}'),
          IconButton(
            tooltip: 'التالي',
            onPressed: page.hasNextPage ? () => onPageChanged(page.page + 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }
}