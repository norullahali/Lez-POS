/// Result of a successful [PosSaleService.processSale] call.
class ProcessSaleResult {
  final int invoiceId;
  final String invoiceNumber;

  const ProcessSaleResult({
    required this.invoiceId,
    required this.invoiceNumber,
  });
}