// lib/core/services/supplier_payment_result.dart

class SupplierPaymentResult {
  const SupplierPaymentResult({
    required this.supplierTransactionId,
    required this.idempotentReplay,
  });

  final int supplierTransactionId;
  final bool idempotentReplay;
}
