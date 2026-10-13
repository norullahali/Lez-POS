// lib/core/services/expense_mutation_save_idempotency_conflict_exception.dart

class OtherIncomeMutationSaveIdempotencyConflictException implements Exception {
  const OtherIncomeMutationSaveIdempotencyConflictException();

  @override
  String toString() =>
      'Other income mutation save idempotency conflict: key reused with different payload';
}
