import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../data/invoice_history_query.dart';
import '../providers/invoice_history_provider.dart';

class InvoiceHistoryFiltersBar extends ConsumerStatefulWidget {
  const InvoiceHistoryFiltersBar({super.key});

  @override
  ConsumerState<InvoiceHistoryFiltersBar> createState() =>
      _InvoiceHistoryFiltersBarState();
}

class _InvoiceHistoryFiltersBarState
    extends ConsumerState<InvoiceHistoryFiltersBar> {
  final _search = TextEditingController();
  static final _df = DateFormat('yyyy/MM/dd');
  static const _debounceMs = 250;
  Timer? _searchDebounce;

  void _applySearchToState(String raw) {
    ref.read(invoiceHistoryUiProvider.notifier).applySearch(raw);
    ref.invalidate(invoiceHistoryPageProvider);
  }

  void _onSearchTextChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      _applySearchToState(raw);
    });
  }

  void _flushSearchNow() {
    _searchDebounce?.cancel();
    _applySearchToState(_search.text);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  String _dateLabel(InvoiceHistoryQuery q) {
    if (q.dateFrom == null && q.dateTo == null) {
      return 'كل التواريخ';
    }
    final a = q.dateFrom != null ? _df.format(q.dateFrom!) : '…';
    final b = q.dateTo != null ? _df.format(q.dateTo!) : '…';
    return '$a — $b';
  }

  Future<void> _pickRange(InvoiceHistoryQuery q) async {
    final now = DateTime.now();
    final initial = (q.dateFrom != null && q.dateTo != null)
        ? DateTimeRange(start: q.dateFrom!, end: q.dateTo!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: DateTime(now.year, now.month, now.day),
          );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(invoiceHistoryUiProvider.notifier).setDateRange(
            picked.start,
            picked.end,
          );
      ref.invalidate(invoiceHistoryPageProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(invoiceHistoryUiProvider);
    final cashiersAsync = ref.watch(invoiceHistoryCashiersProvider);

    return Material(
      color: AppColors.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _search,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  hintText:
                      'بحث مباشر برقم الفاتورة أو العميل أو الكاشير…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: _onSearchTextChanged,
                onSubmitted: (_) => _flushSearchNow(),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _pickRange(q),
              icon: const Icon(Icons.date_range_rounded, size: 20),
              label: Text(_dateLabel(q)),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 200,
              child: cashiersAsync.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, __) => const Text('تعذر تحميل الكاشير'),
                data: (names) {
                  final cashierVal = q.cashierName != null &&
                          names.contains(q.cashierName)
                      ? q.cashierName
                      : null;
                  return DropdownButtonFormField<String?>(
                    key: ValueKey<String?>('cashier_$cashierVal'),
                    isExpanded: true,
                    initialValue: cashierVal,
                    decoration: const InputDecoration(
                      labelText: 'الكاشير',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('الكل'),
                      ),
                      ...names.map(
                        (n) => DropdownMenuItem(value: n, child: Text(n)),
                      ),
                    ],
                    onChanged: (v) {
                      ref.read(invoiceHistoryUiProvider.notifier).setCashier(v);
                      ref.invalidate(invoiceHistoryPageProvider);
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String?>(
                key: ValueKey<String?>('pay_${q.paymentMethod}'),
                isExpanded: true,
                initialValue: q.paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'الدفع',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(value: 'CASH', child: Text('نقدي')),
                  DropdownMenuItem(value: 'CARD', child: Text('بطاقة')),
                  DropdownMenuItem(value: 'DEBT', child: Text('دين')),
                  DropdownMenuItem(value: 'MIXED', child: Text('مختلط')),
                ],
                onChanged: (v) {
                  ref
                      .read(invoiceHistoryUiProvider.notifier)
                      .setPaymentMethod(v);
                  ref.invalidate(invoiceHistoryPageProvider);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'تطبيق البحث فوراً',
              onPressed: _flushSearchNow,
              icon: const Icon(Icons.manage_search_rounded),
            ),
            IconButton(
              tooltip: 'إعادة ضبط الفلاتر',
              onPressed: () {
                _searchDebounce?.cancel();
                ref.read(invoiceHistoryUiProvider.notifier).resetToDefaultRange();
                _search.clear();
                ref.invalidate(invoiceHistoryCashiersProvider);
                ref.invalidate(invoiceHistoryPageProvider);
              },
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
