import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../providers/invoice_history_provider.dart';

class InvoiceHistoryFiltersBar extends ConsumerWidget {
  final TextEditingController searchController;
  final VoidCallback onApplyFilters;

  const InvoiceHistoryFiltersBar({
    super.key,
    required this.searchController,
    required this.onApplyFilters,
  });

  static final _df = DateFormat('yyyy/MM/dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(invoiceHistoryUiProvider);
    final cashiersAsync = ref.watch(invoiceHistoryCashiersProvider);

    String dateLabel() {
      if (q.dateFrom == null && q.dateTo == null) {
        return 'كل التواريخ';
      }
      final a = q.dateFrom != null ? _df.format(q.dateFrom!) : '…';
      final b = q.dateTo != null ? _df.format(q.dateTo!) : '…';
      return '$a — $b';
    }

    Future<void> pickRange() async {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2018),
        lastDate: DateTime(now.year + 1),
        initialDateRange: q.dateFrom != null && q.dateTo != null
            ? DateTimeRange(start: q.dateFrom!, end: q.dateTo!)
            : DateTimeRange(
                start: now.subtract(const Duration(days: 30)),
                end: now,
              ),
        builder: (ctx, child) {
          return Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: ColorScheme.light(
                primary: AppColors.primary,
                surface: Colors.white,
              ),
            ),
            child: child!,
          );
        },
      );
      if (picked == null) return;
      ref.read(invoiceHistoryUiProvider.notifier).setDateRange(
            from: picked.start,
            to: picked.end,
          );
      onApplyFilters();
    }

    return Material(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: searchController,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'بحث: رقم الفاتورة أو اسم العميل',
                  prefixIcon: Icon(Icons.search_rounded, size: 22),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (_) {
                  ref
                      .read(invoiceHistoryUiProvider.notifier)
                      .applySearch(searchController.text);
                  onApplyFilters();
                },
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: pickRange,
              icon: const Icon(Icons.date_range_rounded, size: 20),
              label: Text(
                dateLabel(),
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'خيارات سريعة',
              icon:
                  Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'all', child: Text('كل التواريخ')),
                PopupMenuItem(value: '30', child: Text('آخر 30 يوماً')),
              ],
              onSelected: (v) {
                final n = DateTime.now();
                if (v == 'all') {
                  ref
                      .read(invoiceHistoryUiProvider.notifier)
                      .setDateRange(clear: true);
                } else {
                  final to = DateTime(n.year, n.month, n.day);
                  final from = to.subtract(const Duration(days: 30));
                  ref.read(invoiceHistoryUiProvider.notifier).setDateRange(
                        from: from,
                        to: to,
                      );
                }
                onApplyFilters();
              },
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 200,
              child: cashiersAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, __) => const Text(
                  'تعذر تحميل الكاشيرين',
                  style: TextStyle(fontSize: 12),
                ),
                data: (names) {
                  return DropdownButtonFormField<String?>(
                    value: _dropdownCashierValue(q.cashierName, names),
                    decoration: const InputDecoration(
                      labelText: 'الكاشير',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('الكل'),
                      ),
                      ...names.map(
                        (n) => DropdownMenuItem<String?>(
                          value: n,
                          child: Text(n, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      ref.read(invoiceHistoryUiProvider.notifier).setCashier(v);
                      onApplyFilters();
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String?>(
                value: (q.paymentMethod == null || q.paymentMethod!.isEmpty)
                    ? null
                    : q.paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'طريقة الدفع',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                isExpanded: true,
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'CASH', child: Text('نقدي')),
                  DropdownMenuItem(value: 'CARD', child: Text('بطاقة')),
                  DropdownMenuItem(value: 'DEBT', child: Text('آجل')),
                  DropdownMenuItem(value: 'MIXED', child: Text('مختلط')),
                ],
                onChanged: (v) {
                  ref
                      .read(invoiceHistoryUiProvider.notifier)
                      .setPaymentMethod(v);
                  onApplyFilters();
                },
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () {
                ref
                    .read(invoiceHistoryUiProvider.notifier)
                    .applySearch(searchController.text);
                ref.invalidate(invoiceHistoryCashiersProvider);
                onApplyFilters();
              },
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('تحديث'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _dropdownCashierValue(
    String? selected,
    List<String> names,
  ) {
    if (selected == null || selected.isEmpty) return null;
    final i = names.indexWhere((e) => e == selected);
    return i >= 0 ? selected : null;
  }
}
