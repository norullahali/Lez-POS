// lib/core/services/purchase_save_result.dart

class PurchaseSaveResult {
  const PurchaseSaveResult({
    required this.purchaseInvoiceId,
    required this.purchaseInvoiceNumber,
    required this.idempotentReplay,
  });

  final int purchaseInvoiceId;
  final String purchaseInvoiceNumber;
  final bool idempotentReplay;
}
