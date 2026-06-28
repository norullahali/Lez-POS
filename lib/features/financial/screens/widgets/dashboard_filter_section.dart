import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../reports/core/models/report_filter_model.dart';
import '../../../reports/core/widgets/report_filter_bar.dart';
import '../../providers/dashboard_filter_provider.dart';

/// Dashboard date filter bar -- wired to [dashboardFilterProvider] only.
class DashboardFilterSection extends ConsumerWidget {
  const DashboardFilterSection({
    super.key,
    required this.onRefresh,
    required this.onReset,
  });

  final VoidCallback onRefresh;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(dashboardFilterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportFilterBar(
          filter: filter.dateFilter,
          onFilterChanged: (ReportFilterModel value) =>
              ref.read(dashboardFilterProvider.notifier).setDateFilter(value),
          onRefresh: onRefresh,
          showExport: false,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('\u0625\u0639\u0627\u062f\u0629 \u062a\u0639\u064a\u064a\u0646'),
          ),
        ),
      ],
    );
  }
}