// lib/core/services/expense_creation_result.dart

class ExpenseCreationResult {
  const ExpenseCreationResult({
    required this.expenseRecordId,
    required this.idempotentReplay,
  });

  final int expenseRecordId;
  final bool idempotentReplay;
}