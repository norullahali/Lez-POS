// lib/core/services/customer_invoice_return_idempotency_conflict_exception.dart

class CustomerInvoiceReturnIdempotencyConflictException implements Exception {
  const CustomerInvoiceReturnIdempotencyConflictException();

  @override
  String toString() => 'customer invoice return idempotency conflict';
}