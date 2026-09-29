/// Result of a successful [PosSaleService.processSale] call.
class ProcessSaleResult {
  final int invoiceId;
  final String invoiceNumber;
  final bool idempotentReplay;

  const ProcessSaleResult({
    required this.invoiceId,
    required this.invoiceNumber,
    this.idempotentReplay = false,
  });
}