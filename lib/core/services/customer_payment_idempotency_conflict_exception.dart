// lib/core/services/customer_payment_idempotency_conflict_exception.dart

/// Thrown when the same customer payment idempotency key is reused with
/// different material parameters.
class CustomerPaymentIdempotencyConflictException implements Exception {
  const CustomerPaymentIdempotencyConflictException([
    this.message = 'idempotency key reused with different payment parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}