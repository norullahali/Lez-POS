// lib/core/services/customer_payment_result.dart

class CustomerPaymentResult {
  const CustomerPaymentResult({
    required this.customerTransactionId,
    required this.idempotentReplay,
  });

  final int customerTransactionId;
  final bool idempotentReplay;
}