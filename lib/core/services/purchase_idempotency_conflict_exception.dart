// lib/core/services/purchase_idempotency_conflict_exception.dart

/// Thrown when the same purchase idempotency key is reused with a different
/// purchase fingerprint.
class PurchaseIdempotencyConflictException implements Exception {
  const PurchaseIdempotencyConflictException([
    this.message = 'idempotency key reused with different purchase parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}
