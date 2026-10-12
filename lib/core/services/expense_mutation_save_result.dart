// lib/core/services/expense_mutation_save_result.dart

class ExpenseMutationSaveResult {
  const ExpenseMutationSaveResult({
    required this.expenseRecordId,
    required this.idempotentReplay,
    this.alreadyVoided = false,
  });

  final int expenseRecordId;
  final bool idempotentReplay;

  /// True when void found the row already voided (state idempotent, no new audit).
  final bool alreadyVoided;
}
