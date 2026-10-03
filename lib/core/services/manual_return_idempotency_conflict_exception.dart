// lib/core/services/manual_return_idempotency_conflict_exception.dart

/// Thrown when the same manual return idempotency key is reused with
/// different material parameters.
class ManualReturnIdempotencyConflictException implements Exception {
  const ManualReturnIdempotencyConflictException([
    this.message =
        'idempotency key reused with different manual return parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}
