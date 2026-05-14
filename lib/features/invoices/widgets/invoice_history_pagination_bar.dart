import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/invoice_history_provider.dart';

class InvoiceHistoryPaginationBar extends ConsumerWidget {
  const InvoiceHistoryPaginationBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(invoiceHistoryUiProvider);
    final pageAsync = ref.watch(invoiceHistoryPageProvider);

    return pageAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('خطأ: $e', style: const TextStyle(color: AppColors.error)),
      ),
      data: (page) {
        final totalPages = page.totalPages;
        final start =
            page.totalCount == 0 ? 0 : (q.page * q.pageSize) + 1;
        final end = (q.page * q.pageSize) + page.rows.length;

        return Material(
          color: Colors.white,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                Text(
                  page.totalCount == 0
                      ? 'لا توجد نتائج'
                      : 'عرض $start — $end من ${page.totalCount}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'الصفحة السابقة',
                  onPressed: q.page > 0
                      ? () {
                          ref
                              .read(invoiceHistoryUiProvider.notifier)
                              .setPage(q.page - 1);
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'صفحة ${q.page + 1} / $totalPages',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'الصفحة التالية',
                  onPressed: q.page + 1 < totalPages
                      ? () {
                          ref
                              .read(invoiceHistoryUiProvider.notifier)
                              .setPage(q.page + 1);
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
