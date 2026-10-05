// lib/core/services/supplier_return_posting_result.dart

class SupplierReturnPostingResult {
  const SupplierReturnPostingResult({
    required this.supplierReturnId,
    required this.supplierTransactionId,
    required this.idempotentReplay,
  });

  final int supplierReturnId;
  final int? supplierTransactionId;
  final bool idempotentReplay;
}
