import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:uuid/uuid.dart';
import '../../../../core/services/expense_creation_idempotency_conflict_exception.dart';
import '../../../../core/services/expense_mutation_save_idempotency_conflict_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../features/pos/providers/pos_provider.dart';
import '../../expense_submit_idempotency.dart';
import '../../models/expense_record.dart';
import '../../providers/expense_creation_service_provider.dart';
import '../../providers/expense_mutation_save_service_provider.dart';
import '../../providers/expense_providers.dart';

class ExpenseDialog extends ConsumerStatefulWidget {
  const ExpenseDialog({super.key, this.existing});

  final ExpenseRecord? existing;

  /// When true, the next post-success refresh throws once (B39 widget tests).
  @visibleForTesting
  static bool failNextPostSuccessRefreshForTesting = false;

  @visibleForTesting
  static int postSuccessRefreshCount = 0;

  @visibleForTesting
  static void Function()? testingInvalidateGenerationHook;

  @visibleForTesting
  static void invalidateSubmitGenerationForTesting() {
    testingInvalidateGenerationHook?.call();
  }

  @visibleForTesting
  static void resetExpenseSubmitTestingHooks() {
    failNextPostSuccessRefreshForTesting = false;
    postSuccessRefreshCount = 0;
    testingInvalidateGenerationHook = null;
  }

  @override
  ConsumerState<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends ConsumerState<ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  int? _selectedCategoryId;
  late DateTime _expenseDate;
  late DateTime _paidAt;
  bool _linkSession = false;
  bool _saving = false;
  String? _idempotencyKey;
  String? _pendingFingerprint;
  int _submitGeneration = 0;
  final ExpenseSubmitRunner _submitRunner = ExpenseSubmitRunner();
  String? _pendingServiceFailureMessage;
  VoidCallback? _testingGenerationHook;

  static final _dateFmt = DateFormat('yyyy/MM/dd');
  static const _expenseCreateUuid = Uuid();

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _amountCtrl = TextEditingController(
        text: ex != null ? ex.amount.toStringAsFixed(2) : '');
    _notesCtrl = TextEditingController(text: ex?.notes ?? '');
    _selectedCategoryId = ex?.categoryId;
    _expenseDate = ex?.expenseDate ?? DateTime.now();
    _paidAt = ex?.paidAt ?? DateTime.now();
    _linkSession = ex?.sessionId != null;
    _amountCtrl.addListener(_invalidateSubmitGeneration);
    _notesCtrl.addListener(_invalidateSubmitGeneration);
    _testingGenerationHook = () {
      _submitGeneration++;
    };
    ExpenseDialog.testingInvalidateGenerationHook = _testingGenerationHook;
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_invalidateSubmitGeneration);
    _notesCtrl.removeListener(_invalidateSubmitGeneration);
    if (ExpenseDialog.testingInvalidateGenerationHook ==
        _testingGenerationHook) {
      ExpenseDialog.testingInvalidateGenerationHook = null;
    }
    _testingGenerationHook = null;
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _invalidateSubmitGeneration() {
    if (_saving) return;
    _submitGeneration++;
    _idempotencyKey = null;
  }

  void _resetSaveAttempt() {
    _idempotencyKey = null;
    _pendingFingerprint = null;
  }

  Future<void> _pickDate(bool isExpenseDate) async {
    if (_saving) return;
    final initial = isExpenseDate ? _expenseDate : _paidAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isExpenseDate) {
          _expenseDate = picked;
        } else {
          _paidAt = picked;
        }
        _invalidateSubmitGeneration();
      });
    }
  }

  ExpenseSubmitIntent? _buildSubmitIntent({
    required int userId,
    required int? sessionId,
  }) {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0 || _selectedCategoryId == null) {
      return null;
    }
    final notes = _notesCtrl.text.trim();
    if (widget.existing != null) {
      return ExpenseSubmitIntent.update(
        expenseId: widget.existing!.id!,
        categoryId: _selectedCategoryId!,
        amount: amount,
        expenseDate: _expenseDate,
        paidAt: _paidAt,
        notes: notes,
        sessionId: sessionId,
        updatedBy: userId,
      );
    }
    return ExpenseSubmitIntent.create(
      categoryId: _selectedCategoryId!,
      amount: amount,
      expenseDate: _expenseDate,
      paidAt: _paidAt,
      notes: notes,
      sessionId: sessionId,
      createdBy: userId,
    );
  }

  void _handleSubmitOutcome(ExpenseSubmitOutcome outcome) {
    if (!mounted) return;
    switch (outcome) {
      case ExpenseSubmitOutcome.skippedInFlight:
        break;
      case ExpenseSubmitOutcome.success:
        _resetSaveAttempt();
        if (!context.mounted) return;
        Navigator.of(context).pop(true);
      case ExpenseSubmitOutcome.postSuccessRefreshFailed:
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حفظ المصروف، لكن تعذر تحديث العرض. أعد المحاولة.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      case ExpenseSubmitOutcome.idempotencyConflict:
        _resetSaveAttempt();
        if (!context.mounted) return;
        final isEdit = widget.existing != null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit
                  ? 'تعذر تعديل المصروف: تعارض في عملية الحفظ.'
                  : 'تعذر تسجيل المصروف: تعارض في عملية الحفظ.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      case ExpenseSubmitOutcome.serviceFailure:
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _pendingServiceFailureMessage ?? 'تعذر حفظ المصروف',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        _pendingServiceFailureMessage = null;
      case ExpenseSubmitOutcome.staleCompletion:
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم تجاهل نتيجة حفظ سابقة بعد تغيير البيانات.',
            ),
          ),
        );
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

    if (_saving || _submitRunner.inFlight) return;

    final authState = ref.read(authProvider).valueOrNull;
    final userId = authState?.user?.id ?? 0;
    if (userId <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u064a\u062c\u0628 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0644\u062d\u0641\u0638 \u0627\u0644\u0645\u0635\u0631\u0648\u0641',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final sessionId = _linkSession
        ? ref.read(posSessionProvider).valueOrNull?.id
        : null;

    final intent = _buildSubmitIntent(userId: userId, sessionId: sessionId);
    if (intent == null) return;

    final fingerprint = intent.fingerprintHash;
    if (_pendingFingerprint != null && _pendingFingerprint != fingerprint) {
      _resetSaveAttempt();
    }
    _pendingFingerprint = fingerprint;

    final generation = ++_submitGeneration;
    _idempotencyKey ??= _expenseCreateUuid.v4();
    final submitKey = _idempotencyKey!;

    setState(() => _saving = true);
    try {
      final outcome = await _submitRunner.submit(
        intent: intent,
        idempotencyKey: submitKey,
        isSubmitStillCurrent: () =>
            mounted && generation == _submitGeneration,
        invokeService: (idempotencyKey) async {
          try {
            switch (intent.mode) {
              case ExpenseSubmitMode.create:
                await ref.read(expenseCreationServiceProvider).processCreate(
                      idempotencyKey: idempotencyKey,
                      fingerprintHash: intent.fingerprintHash,
                      categoryId: intent.categoryId,
                      amount: intent.amount,
                      expenseDate: intent.expenseDate,
                      paidAt: intent.paidAt,
                      notes: intent.notes,
                      createdBy: intent.createdBy!,
                      sessionId: intent.sessionId,
                    );
              case ExpenseSubmitMode.update:
                await ref.read(expenseMutationSaveServiceProvider).processUpdate(
                      idempotencyKey: idempotencyKey,
                      fingerprintHash: intent.fingerprintHash,
                      expenseId: intent.expenseId!,
                      categoryId: intent.categoryId,
                      amount: intent.amount,
                      expenseDate: intent.expenseDate,
                      paidAt: intent.paidAt,
                      notes: intent.notes,
                      updatedBy: intent.updatedBy!,
                      sessionId: intent.sessionId,
                    );
            }
          } on ExpenseCreationIdempotencyConflictException {
            rethrow;
          } on ExpenseMutationSaveIdempotencyConflictException {
            rethrow;
          } catch (e) {
            _pendingServiceFailureMessage = e.toString();
            rethrow;
          }
        },
        postSuccessRefresh: () async {
          if (ExpenseDialog.failNextPostSuccessRefreshForTesting) {
            ExpenseDialog.failNextPostSuccessRefreshForTesting = false;
            throw Exception('fail refresh');
          }
          ExpenseDialog.postSuccessRefreshCount++;
          ref.invalidate(expensesProvider);
          ref.invalidate(expenseSummaryProvider);
        },
      );

      _handleSubmitOutcome(outcome);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final isEdit = widget.existing != null;
    final hasSession =
        ref.watch(posSessionProvider).valueOrNull != null;
    final canEdit = !_saving;

    return AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isEdit
            ? '\u062a\u0639\u062f\u064a\u0644 \u0645\u0635\u0631\u0648\u0641'
            : '\u0645\u0635\u0631\u0648\u0641 \u062c\u062f\u064a\u062f',
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
                    final active =
                        cats.where((c) => c.isActive).toList();
                    return DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: const InputDecoration(
                          labelText: '\u0627\u0644\u0641\u0626\u0629 *'),
                      items: active
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: canEdit
                          ? (v) => setState(() {
                                _selectedCategoryId = v;
                                _invalidateSubmitGeneration();
                              })
                          : null,
                      validator: (v) => v == null
                          ? '\u0627\u0644\u0641\u0626\u0629 \u0645\u0637\u0644\u0648\u0628\u0629'
                          : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('expense_dialog_amount'),
                  controller: _amountCtrl,
                  enabled: canEdit,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  decoration: const InputDecoration(
                      labelText: '\u0627\u0644\u0645\u0628\u0644\u063a *'),
                  validator: (v) {
                    final d = double.tryParse(v?.trim() ?? '');
                    if (d == null || d <= 0) {
                      return '\u0627\u062f\u062e\u0644 \u0645\u0628\u0644\u063a\u064b\u0627 \u0635\u062d\u064a\u062d\u064b\u0627';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: canEdit ? () => _pickDate(true) : null,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText:
                          '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0635\u0631\u0641 *',
                      suffixIcon: Icon(Icons.calendar_today_rounded,
                          size: 18),
                    ),
                    child: Text(_dateFmt.format(_expenseDate)),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: canEdit ? () => _pickDate(false) : null,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText:
                          '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u062f\u0641\u0639',
                      suffixIcon: Icon(Icons.calendar_today_rounded,
                          size: 18),
                    ),
                    child: Text(_dateFmt.format(_paidAt)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  enabled: canEdit,
                  decoration: const InputDecoration(
                      labelText:
                          '\u0645\u0644\u0627\u062d\u0638\u0627\u062a'),
                  maxLines: 2,
                ),
                if (hasSession) ...[
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: _linkSession,
                    onChanged: canEdit
                        ? (v) => setState(() {
                              _linkSession = v ?? false;
                              _invalidateSubmitGeneration();
                            })
                        : null,
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
          onPressed:
              _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('\u0625\u0644\u063a\u0627\u0621'),
        ),
        ElevatedButton(
          key: const Key('expense_dialog_save'),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit
                  ? '\u062d\u0641\u0638 \u0627\u0644\u062a\u0639\u062f\u064a\u0644\u0627\u062a'
                  : '\u062a\u0633\u062c\u064a\u0644'),
        ),
      ],
    );
  }
}
