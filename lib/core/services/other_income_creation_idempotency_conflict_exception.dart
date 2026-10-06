// lib/core/services/other_income_creation_idempotency_conflict_exception.dart

/// Thrown when the same other income idempotency key is reused with a different
/// income fingerprint.
class OtherIncomeCreationIdempotencyConflictException implements Exception {
  const OtherIncomeCreationIdempotencyConflictException([
    this.message = 'idempotency key reused with different other income parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}