import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../providers/invoice_history_provider.dart';
import '../widgets/invoice_history_data_table.dart';
import '../widgets/invoice_history_filters_bar.dart';
import '../widgets/invoice_history_pagination_bar.dart';

class InvoiceHistoryScreen extends ConsumerStatefulWidget {
  const InvoiceHistoryScreen({super.key});

  @override
  ConsumerState<InvoiceHistoryScreen> createState() =>
      _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends ConsumerState<InvoiceHistoryScreen> {
  late final TextEditingController _search;

  final _nf = NumberFormat('#,##0');
  final _df = DateFormat('yyyy/MM/dd HH:mm');

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reloadList() {
    ref.invalidate(invoiceHistoryPageProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InvoiceHistoryFiltersBar(
          searchController: _search,
          onApplyFilters: _reloadList,
        ),
        const Divider(height: 1),
        Expanded(
          child: Container(
            color: AppColors.background,
            child: ref.watch(invoiceHistoryPageProvider).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: SelectableText(
                        'تعذر تحميل الفواتير:\n$e',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ),
                  data: (page) {
                    if (page.rows.isEmpty) {
                      return const Center(
                        child: Text(
                          'لا توجد فواتير مطابقة للفلتر الحالي',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    return InvoiceHistoryDataTable(
                      rows: page.rows,
                      nf: _nf,
                      df: _df,
                    );
                  },
                ),
          ),
        ),
        const InvoiceHistoryPaginationBar(),
      ],
    );
  }
}
