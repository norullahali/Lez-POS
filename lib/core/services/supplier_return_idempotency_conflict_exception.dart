// lib/core/services/supplier_return_idempotency_conflict_exception.dart

/// Thrown when the same supplier return idempotency key is reused with
/// different material parameters.
class SupplierReturnIdempotencyConflictException implements Exception {
  const SupplierReturnIdempotencyConflictException([
    this.message = 'idempotency key reused with different return parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}
