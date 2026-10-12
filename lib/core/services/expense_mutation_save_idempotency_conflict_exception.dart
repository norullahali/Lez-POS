// lib/core/services/expense_mutation_save_idempotency_conflict_exception.dart

class ExpenseMutationSaveIdempotencyConflictException implements Exception {
  const ExpenseMutationSaveIdempotencyConflictException();

  @override
  String toString() =>
      'Expense mutation save idempotency conflict: key reused with different payload';
}
