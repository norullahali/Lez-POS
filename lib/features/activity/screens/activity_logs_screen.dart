// lib/features/activity/screens/activity_logs_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/activity/activity_categories.dart';
import '../../../core/activity/activity_severity.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/search_field.dart';
import '../providers/activity_logs_provider.dart';
import '../widgets/activity_log_detail_dialog.dart';
import '../widgets/activity_severity_chip.dart';

class ActivityLogsScreen extends ConsumerStatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  ConsumerState<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends ConsumerState<ActivityLogsScreen> {
  final _dateFormat = DateFormat('yyyy/MM/dd HH:mm:ss');
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _patchFilter(ActivityLogsFilter Function(ActivityLogsFilter f) patch) {
    ref.read(activityLogsFilterProvider.notifier).update((f) => patch(f).copyWith(page: 0));
  }

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(activityLogsPageProvider);
    final filter = ref.watch(activityLogsFilterProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\u0633\u062c\u0644 \u0627\u0644\u0646\u0634\u0627\u0637',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '\u0639\u0631\u0636 \u0648\u062a\u0635\u0641\u064a\u0629 \u0633\u062c\u0644 \u0627\u0644\u0639\u0645\u0644\u064a\u0627\u062a \u0648\u0627\u0644\u0623\u062d\u062f\u0627\u062b \u0641\u064a \u0627\u0644\u0646\u0638\u0627\u0645.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/activity/timeline'),
                icon: const Icon(Icons.timeline_rounded),
                label: const Text('\u0627\u0644\u062c\u062f\u0648\u0644 \u0627\u0644\u0632\u0645\u0646\u064a \u0644\u0644\u0645\u0633\u062a\u062e\u062f\u0645'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: SearchField(
                      hint: '\u0628\u062d\u062b \u0641\u064a \u0627\u0644\u0639\u0646\u0648\u0627\u0646 \u0623\u0648 \u0627\u0644\u0648\u0635\u0641...',
                      controller: _searchController,
                      onChanged: (v) => _patchFilter((f) => f.copyWith(
                            search: v.trim().isEmpty ? null : v.trim(),
                            clearSearch: v.trim().isEmpty,
                          )),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      value: filter.category,
                      decoration: const InputDecoration(
                        labelText: '\u0627\u0644\u0641\u0626\u0629',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('\u0643\u0644 \u0627\u0644\u0641\u0626\u0627\u062a')),
                        ...ActivityCategories.all.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c,
                            child: Text(ActivityCategories.labelAr(c)),
                          ),
                        ),
                      ],
                      onChanged: (v) => _patchFilter((f) => f.copyWith(
                            category: v,
                            clearCategory: v == null,
                          )),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String?>(
                      value: filter.severity,
                      decoration: const InputDecoration(
                        labelText: '\u0627\u0644\u0623\u0647\u0645\u064a\u0629',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('\u0643\u0644 \u0627\u0644\u0645\u0633\u062a\u0648\u064a\u0627\u062a')),
                        ...ActivitySeverity.all.map(
                          (s) => DropdownMenuItem<String?>(
                            value: s,
                            child: Text(ActivitySeverity.labelAr(s)),
                          ),
                        ),
                      ],
                      onChanged: (v) => _patchFilter((f) => f.copyWith(
                            severity: v,
                            clearSeverity: v == null,
                          )),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      ref.read(activityLogsFilterProvider.notifier).state = const ActivityLogsFilter();
                    },
                    icon: const Icon(Icons.filter_alt_off_rounded),
                    label: const Text('\u0625\u0639\u0627\u062f\u0629 \u062a\u0639\u064a\u064a\u0646'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: pageAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: SelectableText('\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u0633\u062c\u0644:\n$e')),
                data: (page) {
                  if (page.items.isEmpty) {
                    return const Center(child: Text('\u0644\u0627 \u062a\u0648\u062c\u062f \u0633\u062c\u0644\u0627\u062a \u0645\u0637\u0627\u0628\u0642\u0629 \u0644\u0644\u062a\u0635\u0641\u064a\u0629'));
                  }
                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              showCheckboxColumn: false,
                              columnSpacing: 20,
                              headingRowColor: WidgetStateProperty.all(AppColors.surfaceVariant),
                              columns: const [
                                DataColumn(label: Text('\u0627\u0644\u0648\u0642\u062a')),
                                DataColumn(label: Text('\u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645')),
                                DataColumn(label: Text('\u0627\u0644\u0641\u0626\u0629')),
                                DataColumn(label: Text('\u0627\u0644\u0623\u0647\u0645\u064a\u0629')),
                                DataColumn(label: Text('\u0627\u0644\u0639\u0646\u0648\u0627\u0646')),
                                DataColumn(label: Text('\u0627\u0644\u0625\u062c\u0631\u0627\u0621')),
                              ],
                              rows: page.items.map((log) {
                                return DataRow(
                                  onSelectChanged: (_) => showActivityLogDetailDialog(context, log),
                                  cells: [
                                    DataCell(Text(_dateFormat.format(log.createdAt), style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(log.usernameSnapshot ?? '\u2014')),
                                    DataCell(Text(ActivityCategories.labelAr(log.category))),
                                    DataCell(ActivitySeverityChip(severity: log.severity)),
                                    DataCell(
                                      SizedBox(
                                        width: 260,
                                        child: Text(log.title, overflow: TextOverflow.ellipsis, maxLines: 2),
                                      ),
                                    ),
                                    DataCell(Text(log.action)),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      _PaginationBar(
                        filter: page.filter,
                        total: page.total,
                        onPageChanged: (p) => ref.read(activityLogsFilterProvider.notifier).update((f) => f.copyWith(page: p)),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.filter,
    required this.total,
    required this.onPageChanged,
  });

  final ActivityLogsFilter filter;
  final int total;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final totalPages = total == 0 ? 1 : ((total - 1) ~/ filter.pageSize) + 1;
    final from = total == 0 ? 0 : filter.page * filter.pageSize + 1;
    final to = (filter.page + 1) * filter.pageSize;
    final shownTo = to > total ? total : to;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            '\u0639\u0631\u0636 $from\u2013$shownTo \u0645\u0646 $total',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const Spacer(),
          IconButton(
            tooltip: '\u0627\u0644\u0635\u0641\u062d\u0629 \u0627\u0644\u0633\u0627\u0628\u0642\u0629',
            onPressed: filter.page > 0 ? () => onPageChanged(filter.page - 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          Text('${filter.page + 1} / $totalPages', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: '\u0627\u0644\u0635\u0641\u062d\u0629 \u0627\u0644\u062a\u0627\u0644\u064a\u0629',
            onPressed: filter.page + 1 < totalPages ? () => onPageChanged(filter.page + 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
        ],
      ),
    );
  }
}
