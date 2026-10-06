// lib/core/services/expense_creation_idempotency_conflict_exception.dart

/// Thrown when the same expense idempotency key is reused with a different
/// expense fingerprint.
class ExpenseCreationIdempotencyConflictException implements Exception {
  const ExpenseCreationIdempotencyConflictException([
    this.message = 'idempotency key reused with different expense parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}