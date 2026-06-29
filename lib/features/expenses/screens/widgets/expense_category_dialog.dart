import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/expense_category.dart';
import '../../providers/expense_providers.dart';

class ExpenseCategoryDialog extends ConsumerStatefulWidget {
  const ExpenseCategoryDialog({super.key, this.existing});

  final ExpenseCategory? existing;

  @override
  ConsumerState<ExpenseCategoryDialog> createState() =>
      _ExpenseCategoryDialogState();
}

class _ExpenseCategoryDialogState
    extends ConsumerState<ExpenseCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl =
        TextEditingController(text: widget.existing?.description ?? '');
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final isEdit = widget.existing != null;
      if (isEdit) {
        await repo.updateCategory(widget.existing!.copyWith(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          isActive: _isActive,
        ));
      } else {
        await repo.createCategory(ExpenseCategory(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          isActive: _isActive,
          createdAt: DateTime.now(),
        ));
      }
      ref.invalidate(expenseCategoriesProvider);
      ref.invalidate(expenseSummaryProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isEdit
            ? '\u062a\u0639\u062f\u064a\u0644 \u0641\u0626\u0629 \u0645\u0635\u0631\u0648\u0641'
            : '\u0625\u0636\u0627\u0641\u0629 \u0641\u0626\u0629 \u0645\u0635\u0631\u0648\u0641',
        textDirection: TextDirection.rtl,
      ),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                    labelText: '\u0627\u0633\u0645 \u0627\u0644\u0641\u0626\u0629 *'),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true)
                        ? '\u0627\u0644\u0627\u0633\u0645 \u0645\u0637\u0644\u0648\u0628'
                        : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                    labelText: '\u0627\u0644\u0648\u0635\u0641'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text('\u0646\u0634\u0637',
                    textDirection: TextDirection.rtl),
                contentPadding: EdgeInsets.zero,
              ),
            ],
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
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit
                  ? '\u062d\u0641\u0638 \u0627\u0644\u062a\u0639\u062f\u064a\u0644\u0627\u062a'
                  : '\u0625\u0636\u0627\u0641\u0629'),
        ),
      ],
    );
  }
}