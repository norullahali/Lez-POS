// lib/core/services/quick_return_idempotency_conflict_exception.dart

/// Thrown when the same quick return idempotency key is reused with
/// different material parameters.
class QuickReturnIdempotencyConflictException implements Exception {
  const QuickReturnIdempotencyConflictException([
    this.message =
        'idempotency key reused with different quick return parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}
