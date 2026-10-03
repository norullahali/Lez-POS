// lib/core/services/supplier_payment_idempotency_conflict_exception.dart

/// Thrown when the same supplier payment idempotency key is reused with
/// different material parameters.
class SupplierPaymentIdempotencyConflictException implements Exception {
  const SupplierPaymentIdempotencyConflictException([
    this.message = 'idempotency key reused with different payment parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}
