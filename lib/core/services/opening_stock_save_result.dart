// lib/core/services/opening_stock_save_result.dart

class OpeningStockSaveResult {
  const OpeningStockSaveResult({
    required this.sealedProductIds,
    required this.idempotentReplay,
  });

  final List<int> sealedProductIds;
  final bool idempotentReplay;
}
