import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../providers/invoice_history_provider.dart';
import '../widgets/invoice_details_dialog.dart';
import '../widgets/invoice_history_data_table.dart';
import '../widgets/invoice_history_filters_bar.dart';
import '../widgets/invoice_history_pagination_bar.dart';

class InvoiceHistoryScreen extends ConsumerWidget {
  const InvoiceHistoryScreen({super.key});

  void _openDetail(BuildContext context, int invoiceId) {
    showDialog<void>(
      context: context,
      builder: (ctx) => InvoiceDetailsDialog(invoiceId: invoiceId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(invoiceHistoryPageProvider);
    final nf = NumberFormat('#,##0.##');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سجل المبيعات / الفواتير',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'انقر على صف لعرض تفاصيل الفاتورة.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 20),
            const InvoiceHistoryFiltersBar(),
            const SizedBox(height: 16),
            Expanded(
              child: pageAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Center(
                  child: SelectableText(
                    'تعذر تحميل الفواتير:\n$e',
                    textAlign: TextAlign.center,
                  ),
                ),
                data: (page) {
                  if (page.rows.isEmpty) {
                    return const Center(
                      child: Text('لا توجد فواتير مطابقة للفلاتر الحالية.'),
                    );
                  }
                  return InvoiceHistoryDataTable(
                    rows: page.rows,
                    nf: nf,
                    onOpenInvoice: (id) => _openDetail(context, id),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const InvoiceHistoryPaginationBar(),
          ],
        ),
      ),
    );
  }
}
