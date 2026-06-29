import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../features/auth/permissions/permission_keys.dart';
import '../../../features/auth/widgets/permission_gate.dart';
import '../models/expense_record.dart';
import '../providers/expense_providers.dart';
import 'widgets/expense_category_dialog.dart';
import 'widgets/expense_dialog.dart';

class ExpenseScreen extends ConsumerWidget {
  const ExpenseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _HeaderRow(),
          SizedBox(height: 16),
          _SummarySection(),
          SizedBox(height: 16),
          _FilterBar(),
          SizedBox(height: 16),
          Expanded(child: _ExpenseTable()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Header
// ─────────────────────────────────────────
class _HeaderRow extends ConsumerWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        PermissionVisibility(
          permission: PermissionKeys.financialExpensesCreate,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              '\u0625\u0636\u0627\u0641\u0629 \u0645\u0635\u0631\u0648\u0641',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () => showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const ExpenseDialog(),
            ).then((_) {
              ref.invalidate(expensesProvider);
              ref.invalidate(expenseSummaryProvider);
            }),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.category_rounded, size: 18),
          label: const Text(
              '\u0625\u062f\u0627\u0631\u0629 \u0627\u0644\u0641\u0626\u0627\u062a'),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const _CategoryManagerDialog(),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '\u062a\u062d\u062f\u064a\u062b',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () {
            ref.invalidate(expensesProvider);
            ref.invalidate(expenseSummaryProvider);
            ref.invalidate(expenseCategoriesProvider);
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Category Manager dialog — proper ConsumerWidget
// ─────────────────────────────────────────
class _CategoryManagerDialog extends ConsumerWidget {
  const _CategoryManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(expenseCategoriesProvider);
    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              '\u0625\u062f\u0627\u0631\u0629 \u0641\u0626\u0627\u062a \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a',
            ),
          ),
          PermissionVisibility(
            permission: PermissionKeys.financialExpensesCreate,
            child: IconButton(
              icon: const Icon(Icons.add_rounded, color: AppColors.accent),
              tooltip:
                  '\u0625\u0636\u0627\u0641\u0629 \u0641\u0626\u0629',
              onPressed: () => showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const ExpenseCategoryDialog(),
              ).then((_) => ref.invalidate(expenseCategoriesProvider)),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 400,
        child: catsAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(e.toString())),
          data: (cats) => ListView.separated(
            itemCount: cats.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final cat = cats[i];
              return ListTile(
                title: Text(cat.name),
                subtitle: cat.description.isNotEmpty
                    ? Text(cat.description)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cat.isActive
                            ? AppColors.successLight
                            : AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        cat.isActive
                            ? '\u0646\u0634\u0637'
                            : '\u0645\u0639\u0637\u0644',
                        style: TextStyle(
                          fontSize: 11,
                          color: cat.isActive
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    PermissionVisibility(
                      permission: PermissionKeys.financialExpensesEdit,
                      child: IconButton(
                        icon: const Icon(Icons.edit_rounded,
                            size: 18, color: AppColors.primary),
                        tooltip: '\u062a\u0639\u062f\u064a\u0644',
                        onPressed: () => showDialog(
                          context: ctx,
                          barrierDismissible: false,
                          builder: (_) =>
                              ExpenseCategoryDialog(existing: cat),
                        ).then((_) =>
                            ref.invalidate(expenseCategoriesProvider)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('\u0625\u063a\u0644\u0627\u0642'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Summary cards
// ─────────────────────────────────────────
class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  static final _currFmt =
      NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(expenseSummaryProvider);
    return summaryAsync.when(
      loading: () => const _SummaryGrid(
        activeCount: '-',
        totalAmount: '-',
        catCount: '-',
        voidedCount: '-',
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) => _SummaryGrid(
        activeCount: s.activeCount.toString(),
        totalAmount: _currFmt.format(s.totalAmount),
        catCount: s.categoryCount.toString(),
        voidedCount: s.voidedCount.toString(),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.activeCount,
    required this.totalAmount,
    required this.catCount,
    required this.voidedCount,
  });

  final String activeCount;
  final String totalAmount;
  final String catCount;
  final String voidedCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title:
                '\u0639\u062f\u062f \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a',
            value: activeCount,
            icon: Icons.receipt_long_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title:
                '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a',
            value: totalAmount,
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title: '\u0639\u062f\u062f \u0627\u0644\u0641\u0626\u0627\u062a',
            value: catCount,
            icon: Icons.category_rounded,
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            title:
                '\u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a \u0627\u0644\u0645\u0644\u063a\u0627\u0629',
            value: voidedCount,
            icon: Icons.cancel_outlined,
            color: AppColors.error,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// Filter bar
// ─────────────────────────────────────────
class _FilterBar extends ConsumerWidget {
  const _FilterBar();

  static final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(expensesFilterProvider);
    final catsAsync = ref.watch(expenseCategoriesProvider);
    final notifier = ref.read(expensesFilterProvider.notifier);

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 180,
          child: catsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (cats) {
              final active = cats.where((c) => c.isActive).toList();
              return DropdownButtonFormField<int?>(
                value: filter.categoryId,
                decoration: InputDecoration(
                  labelText: '\u0627\u0644\u0641\u0626\u0629',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem<int?>(
                      value: null,
                      child: Text('\u0627\u0644\u0643\u0644')),
                  ...active.map((c) => DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text(c.name,
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => notifier.setCategoryId(v),
              );
            },
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_rounded, size: 16),
          label: Text(
            filter.dateFrom != null
                ? '${_dateFmt.format(filter.dateFrom!)} - ${filter.dateTo != null ? _dateFmt.format(filter.dateTo!) : "..."}'
                : '\u0627\u0644\u062a\u0627\u0631\u064a\u062e',
            style: const TextStyle(fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate:
                  DateTime.now().add(const Duration(days: 1)),
              initialDateRange:
                  filter.dateFrom != null && filter.dateTo != null
                      ? DateTimeRange(
                          start: filter.dateFrom!, end: filter.dateTo!)
                      : null,
            );
            if (range != null) {
              notifier.setDateRange(range.start, range.end);
            }
          },
        ),
        if (filter.dateFrom != null)
          IconButton(
            icon: const Icon(Icons.clear_rounded, size: 16),
            tooltip: '\u0645\u0633\u062d \u0627\u0644\u062a\u0627\u0631\u064a\u062e',
            onPressed: () => notifier.setDateRange(null, null),
          ),
        FilterChip(
          label: const Text(
            '\u062a\u0636\u0645\u064a\u0646 \u0627\u0644\u0645\u0644\u063a\u0627\u0629',
            style: TextStyle(fontSize: 12),
          ),
          selected: filter.includeVoided,
          onSelected: notifier.setIncludeVoided,
          backgroundColor: AppColors.surface,
          selectedColor: AppColors.errorLight,
          checkmarkColor: AppColors.error,
          labelStyle: TextStyle(
            color: filter.includeVoided
                ? AppColors.error
                : AppColors.textVariant,
          ),
        ),
        if (filter.categoryId != null ||
            filter.dateFrom != null ||
            filter.includeVoided)
          TextButton.icon(
            icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
            label: const Text(
              '\u0645\u0633\u062d \u0627\u0644\u0641\u0644\u0627\u062a\u0631',
              style: TextStyle(fontSize: 12),
            ),
            onPressed: notifier.reset,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────
// Expense Table
// ─────────────────────────────────────────
class _ExpenseTable extends ConsumerWidget {
  const _ExpenseTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final catsAsync = ref.watch(expenseCategoriesProvider);
    final usersAsync = ref.watch(usersMapForExpensesProvider);

    final catMap = catsAsync.valueOrNull != null
        ? {for (final c in catsAsync.valueOrNull!) if (c.id != null) c.id!: c.name}
        : <int, String>{};
    final userMap = usersAsync.valueOrNull ?? <int, String>{};

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Expanded(
            child: expensesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  '\u062d\u062f\u062b \u062e\u0637\u0623: $e',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
              data: (page) => page.items.isEmpty
                  ? const Center(
                      child: Text(
                        '\u0644\u0627 \u062a\u0648\u062c\u062f \u0645\u0635\u0631\u0648\u0641\u0627\u062a',
                        style:
                            TextStyle(color: AppColors.textHint),
                      ),
                    )
                  : SingleChildScrollView(
                      child: _DataTable(
                        items: page.items,
                        catMap: catMap,
                        userMap: userMap,
                      ),
                    ),
            ),
          ),
          const Divider(height: 1),
          const _PaginationBar(),
        ],
      ),
    );
  }
}

class _DataTable extends ConsumerWidget {
  const _DataTable({
    required this.items,
    required this.catMap,
    required this.userMap,
  });

  final List<ExpenseRecord> items;
  final Map<int, String> catMap;
  final Map<int, String> userMap;

  static final _dateFmt = DateFormat('yyyy/MM/dd');
  static final _currFmt =
      NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DataTable(
      columnSpacing: 16,
      headingRowColor:
          WidgetStateProperty.all(AppColors.surfaceVariant),
      columns: const [
        DataColumn(
            label: Text('\u0627\u0644\u062a\u0627\u0631\u064a\u062e',
                style: TextStyle(fontWeight: FontWeight.w700))),
        DataColumn(
            label: Text('\u0627\u0644\u0641\u0626\u0629',
                style: TextStyle(fontWeight: FontWeight.w700))),
        DataColumn(
            label: Text('\u0627\u0644\u0645\u0628\u0644\u063a',
                style: TextStyle(fontWeight: FontWeight.w700)),
            numeric: true),
        DataColumn(
            label: Text('\u0627\u0644\u0648\u0635\u0641',
                style: TextStyle(fontWeight: FontWeight.w700))),
        DataColumn(
            label: Text(
                '\u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645',
                style: TextStyle(fontWeight: FontWeight.w700))),
        DataColumn(
            label: Text('\u0627\u0644\u062d\u0627\u0644\u0629',
                style: TextStyle(fontWeight: FontWeight.w700))),
        DataColumn(
            label: Text(
                '\u0625\u062c\u0631\u0627\u0621\u0627\u062a',
                style: TextStyle(fontWeight: FontWeight.w700))),
      ],
      rows: items.map((e) {
        return DataRow(
          cells: [
            DataCell(Text(_dateFmt.format(e.paidAt),
                style: const TextStyle(fontSize: 13))),
            DataCell(Text(catMap[e.categoryId] ?? '#${e.categoryId}',
                style: const TextStyle(fontSize: 13))),
            DataCell(Text(_currFmt.format(e.amount),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600))),
            DataCell(Text(
              e.notes.length > 30
                  ? '${e.notes.substring(0, 30)}...'
                  : e.notes,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            )),
            DataCell(Text(
                userMap[e.createdBy] ??
                    '\u0645\u0633\u062a\u062e\u062f\u0645 ${e.createdBy}',
                style: const TextStyle(fontSize: 13))),
            DataCell(_StatusBadge(isVoided: e.isVoided)),
            DataCell(_ActionButtons(record: e)),
          ],
        );
      }).toList(),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isVoided});
  final bool isVoided;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isVoided ? AppColors.errorLight : AppColors.successLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isVoided
            ? '\u0645\u0644\u063a\u064a'
            : '\u0646\u0634\u0637',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isVoided ? AppColors.error : AppColors.success,
        ),
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.record});
  final ExpenseRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (record.isVoided) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PermissionVisibility(
          permission: PermissionKeys.financialExpensesEdit,
          child: IconButton(
            icon: const Icon(Icons.edit_rounded,
                size: 17, color: AppColors.primary),
            tooltip: '\u062a\u0639\u062f\u064a\u0644',
            onPressed: () => showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => ExpenseDialog(existing: record),
            ).then((_) {
              ref.invalidate(expensesProvider);
              ref.invalidate(expenseSummaryProvider);
            }),
          ),
        ),
        PermissionVisibility(
          permission: PermissionKeys.financialExpensesDelete,
          child: IconButton(
            icon: const Icon(Icons.cancel_outlined,
                size: 17, color: AppColors.error),
            tooltip:
                '\u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u0645\u0635\u0631\u0648\u0641',
            onPressed: () => _confirmVoid(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title:
          '\u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u0645\u0635\u0631\u0648\u0641',
      message:
          '\u0647\u0644 \u0623\u0646\u062a \u0645\u062a\u0623\u0643\u062f \u0645\u0646 \u0625\u0644\u063a\u0627\u0621 \u0647\u0630\u0627 \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u061f',
      confirmLabel:
          '\u0646\u0639\u0645\u060c \u0625\u0644\u063a\u0627\u0621',
      confirmColor: AppColors.error,
    );
    if (!confirmed) return;
    try {
      await ref.read(expenseRepositoryProvider).voidExpense(record.id!);
      ref.invalidate(expensesProvider);
      ref.invalidate(expenseSummaryProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}

// ─────────────────────────────────────────
// Pagination
// ─────────────────────────────────────────
class _PaginationBar extends ConsumerWidget {
  const _PaginationBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(expensesFilterProvider);
    final notifier = ref.read(expensesFilterProvider.notifier);
    final expensesAsync = ref.watch(expensesProvider);

    final totalPages = expensesAsync.valueOrNull?.totalPages ?? 1;
    final currentPage = filter.page;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: '\u0627\u0644\u0633\u0627\u0628\u0642',
            onPressed: currentPage > 0
                ? () => notifier.setPage(currentPage - 1)
                : null,
          ),
          Text(
            '\u0635\u0641\u062d\u0629 ${currentPage + 1} \u0645\u0646 $totalPages',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: '\u0627\u0644\u062a\u0627\u0644\u064a',
            onPressed: currentPage < totalPages - 1
                ? () => notifier.setPage(currentPage + 1)
                : null,
          ),
          const SizedBox(width: 16),
          if (expensesAsync.valueOrNull != null)
            Text(
              '${expensesAsync.valueOrNull!.totalCount} \u0639\u0646\u0635\u0631',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textHint),
            ),
        ],
      ),
    );
  }
}