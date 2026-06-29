import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../../../core/theme/app_colors.dart';
import '../../other_income/models/other_income_record.dart';
import '../../other_income/providers/other_income_providers.dart';

/// View-only details dialog for an OTHER_INCOME Cash Ledger row (Phase 4.3.3).
/// Opens from the Cash Ledger drill-down. No edit, void, or save actions.
class OtherIncomeDetailsDialog extends ConsumerStatefulWidget {
  const OtherIncomeDetailsDialog({super.key, required this.incomeId});

  final int incomeId;

  @override
  ConsumerState<OtherIncomeDetailsDialog> createState() =>
      _OtherIncomeDetailsDialogState();
}

class _OtherIncomeDetailsDialogState
    extends ConsumerState<OtherIncomeDetailsDialog> {
  OtherIncomeRecord? _record;
  bool _loading = true;
  String? _errorMsg;

  static final _dateFmt = DateFormat('yyyy/MM/dd');
  static final _currFmt =
      NumberFormat.currency(locale: 'ar', symbol: '', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final record = await ref
          .read(otherIncomeRepositoryProvider)
          .getIncomeById(widget.incomeId);
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMsg = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(otherIncomeCategoriesProvider);
    final usersAsync = ref.watch(usersMapForIncomeProvider);

    final catMap = catsAsync.valueOrNull != null
        ? {
            for (final c in catsAsync.valueOrNull!)
              if (c.id != null) c.id!: c.name
          }
        : <int, String>{};
    final userMap = usersAsync.valueOrNull ?? <int, String>{};

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('\u062a\u0641\u0627\u0635\u064a\u0644 \u0627\u0644\u0625\u064a\u0631\u0627\u062f'),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : _errorMsg != null
                ? Text(
                    _errorMsg!,
                    style: const TextStyle(color: AppColors.error),
                  )
                : _record == null
                    ? const Text(
                        '\u0627\u0644\u0633\u062c\u0644 \u063a\u064a\u0631 \u0645\u0648\u062c\u0648\u062f \u0623\u0648 \u062a\u0645 \u062d\u0630\u0641\u0647.',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    : _DetailsBody(
                        record: _record!,
                        catMap: catMap,
                        userMap: userMap,
                        dateFmt: _dateFmt,
                        currFmt: _currFmt,
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

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({
    required this.record,
    required this.catMap,
    required this.userMap,
    required this.dateFmt,
    required this.currFmt,
  });

  final OtherIncomeRecord record;
  final Map<int, String> catMap;
  final Map<int, String> userMap;
  final DateFormat dateFmt;
  final NumberFormat currFmt;

  @override
  Widget build(BuildContext context) {
    final isVoided = record.isVoided;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DetailRow(
          label: '\u0627\u0644\u0641\u0626\u0629',
          value: catMap[record.categoryId] ?? '#${record.categoryId}',
        ),
        _DetailRow(
          label: '\u0627\u0644\u0645\u0628\u0644\u063a',
          value: currFmt.format(record.amount),
          valueStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.success,
          ),
        ),
        _DetailRow(
          label: '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0625\u064a\u0631\u0627\u062f',
          value: dateFmt.format(record.incomeDate),
        ),
        _DetailRow(
          label: '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0627\u0633\u062a\u0644\u0627\u0645',
          value: dateFmt.format(record.receivedAt),
        ),
        _DetailRow(
          label: '\u0627\u0644\u0645\u0644\u0627\u062d\u0638\u0627\u062a',
          value: record.notes.trim().isEmpty
              ? '\u2014'
              : record.notes,
        ),
        _DetailRow(
          label: '\u0627\u0644\u062c\u0644\u0633\u0629',
          value: record.sessionId != null
              ? '#${record.sessionId}'
              : '\u2014',
        ),
        _DetailRow(
          label: '\u0623\u0646\u0634\u0626 \u0628\u0648\u0627\u0633\u0637\u0629',
          value: userMap[record.createdBy] ??
              '\u0645\u0633\u062a\u062e\u062f\u0645 ${record.createdBy}',
        ),
        _DetailRow(
          label: '\u0627\u0644\u062d\u0627\u0644\u0629',
          value: isVoided
              ? '\u0645\u0644\u063a\u064a'
              : '\u0646\u0634\u0637',
          valueStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: isVoided ? AppColors.error : AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: valueStyle ??
                  Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}