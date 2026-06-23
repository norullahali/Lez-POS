import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../features/pos/providers/pos_provider.dart';
import '../../models/other_income_record.dart';
import '../../providers/other_income_providers.dart';

class OtherIncomeDialog extends ConsumerStatefulWidget {
  const OtherIncomeDialog({super.key, this.existing});

  final OtherIncomeRecord? existing;

  @override
  ConsumerState<OtherIncomeDialog> createState() => _OtherIncomeDialogState();
}

class _OtherIncomeDialogState extends ConsumerState<OtherIncomeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  int? _selectedCategoryId;
  late DateTime _incomeDate;
  late DateTime _receivedAt;
  bool _linkSession = false;
  bool _saving = false;

  static final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _amountCtrl = TextEditingController(
        text: ex != null ? ex.amount.toStringAsFixed(2) : '');
    _notesCtrl = TextEditingController(text: ex?.notes ?? '');
    _selectedCategoryId = ex?.categoryId;
    _incomeDate = ex?.incomeDate ?? DateTime.now();
    _receivedAt = ex?.receivedAt ?? DateTime.now();
    _linkSession = ex?.sessionId != null;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isIncomeDate) async {
    final initial = isIncomeDate ? _incomeDate : _receivedAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isIncomeDate) {
          _incomeDate = picked;
        } else {
          _receivedAt = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u064a\u0631\u062c\u0649 \u0627\u062e\u062a\u064a\u0627\u0631 \u0627\u0644\u0641\u0626\u0629'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u0627\u0644\u0645\u0628\u0644\u063a \u063a\u064a\u0631 \u0635\u062d\u064a\u062d'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(otherIncomeRepositoryProvider);
      final authState = ref.read(authProvider).valueOrNull;
      final userId = authState?.user?.id ?? 0;
      final isEdit = widget.existing != null;
      final activeSession = ref.read(posSessionProvider).valueOrNull;
      // Case D: editing with no active session → preserve the original sessionId.
      // Case A/B/C: resolve from checkbox state against the current active session.
      final int? sessionId = (isEdit && activeSession == null)
          ? widget.existing!.sessionId
          : (_linkSession ? activeSession?.id : null);
      if (isEdit) {
        await repo.updateIncome(widget.existing!.copyWith(
          categoryId: _selectedCategoryId!,
          amount: amount,
          incomeDate: _incomeDate,
          receivedAt: _receivedAt,
          notes: _notesCtrl.text.trim(),
          sessionId: sessionId,
        ));
      } else {
        await repo.createIncome(OtherIncomeRecord(
          categoryId: _selectedCategoryId!,
          amount: amount,
          incomeDate: _incomeDate,
          receivedAt: _receivedAt,
          notes: _notesCtrl.text.trim(),
          sessionId: sessionId,
          createdBy: userId,
          isVoided: false,
          createdAt: DateTime.now(),
        ));
      }
      ref.invalidate(otherIncomeProvider);
      ref.invalidate(otherIncomeSummaryProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(otherIncomeCategoriesProvider);
    final isEdit = widget.existing != null;
    final hasSession = ref.watch(posSessionProvider).valueOrNull != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isEdit
            ? '\u062a\u0639\u062f\u064a\u0644 \u0625\u064a\u0631\u0627\u062f'
            : '\u0625\u064a\u0631\u0627\u062f \u062c\u062f\u064a\u062f',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                categoriesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (cats) {
                    final active = cats.where((c) => c.isActive).toList();
                    return DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                          labelText: '\u0627\u0644\u0641\u0626\u0629 *'),
                      items: active
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedCategoryId = v),
                      validator: (v) => v == null
                          ? '\u0627\u0644\u0641\u0626\u0629 \u0645\u0637\u0644\u0648\u0628\u0629'
                          : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: '\u0627\u0644\u0645\u0628\u0644\u063a *'),
                  validator: (v) {
                    final d = double.tryParse(v?.trim() ?? '');
                    if (d == null || d <= 0) {
                      return '\u0623\u062f\u062e\u0644 \u0645\u0628\u0644\u063a\u064b\u0627 \u0635\u062d\u064a\u062d\u064b\u0627';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _pickDate(true),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0625\u064a\u0631\u0627\u062f *',
                      suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                    ),
                    child: Text(_dateFmt.format(_incomeDate)),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _pickDate(false),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0627\u0633\u062a\u0644\u0627\u0645',
                      suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                    ),
                    child: Text(_dateFmt.format(_receivedAt)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                      labelText: '\u0645\u0644\u0627\u062d\u0638\u0627\u062a'),
                  maxLines: 2,
                ),
                if (hasSession) ...[
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: _linkSession,
                    onChanged: (v) =>
                        setState(() => _linkSession = v ?? false),
                    title: const Text(
                      '\u0631\u0628\u0637 \u0628\u0627\u0644\u062c\u0644\u0633\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629',
                      style: TextStyle(fontSize: 13),
                    ),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('\u0625\u0644\u063a\u0627\u0621'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit
                  ? '\u062d\u0641\u0638 \u0627\u0644\u062a\u0639\u062f\u064a\u0644\u0627\u062a'
                  : '\u062a\u0633\u062c\u064a\u0644'),
        ),
      ],
    );
  }
}