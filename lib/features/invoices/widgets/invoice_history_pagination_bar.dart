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
      error: (_, __) => const SizedBox.shrink(),
      data: (page) {
        final totalPages = page.totalPages;
        final start = page.totalCount == 0
            ? 0
            : (q.page * q.pageSize) + 1;
        final end = (q.page * q.pageSize + page.rows.length)
            .clamp(0, page.totalCount);

        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Text(
                page.totalCount == 0
                    ? 'لا نتائج'
                    : 'عرض $start — $end من ${page.totalCount}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'السابق',
                onPressed: q.page > 0
                    ? () {
                        ref
                            .read(invoiceHistoryUiProvider.notifier)
                            .setPage(q.page - 1);
                        ref.invalidate(invoiceHistoryPageProvider);
                      }
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'صفحة ${q.page + 1} / $totalPages',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: 'التالي',
                onPressed: q.page + 1 < totalPages
                    ? () {
                        ref
                            .read(invoiceHistoryUiProvider.notifier)
                            .setPage(q.page + 1);
                        ref.invalidate(invoiceHistoryPageProvider);
                      }
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        );
      },
    );
  }
}
