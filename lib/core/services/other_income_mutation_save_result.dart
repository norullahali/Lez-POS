// lib/core/services/expense_mutation_save_result.dart

class OtherIncomeMutationSaveResult {
  const OtherIncomeMutationSaveResult({
    required this.otherIncomeRecordId,
    required this.idempotentReplay,
    this.alreadyVoided = false,
  });

  final int otherIncomeRecordId;
  final bool idempotentReplay;

  /// True when void found the row already voided (state idempotent, no new audit).
  final bool alreadyVoided;
}
