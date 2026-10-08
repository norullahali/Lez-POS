// lib/core/services/stock_adjustment_save_result.dart

/// Result of a stock adjustment save operation (B21).
class StockAdjustmentSaveResult {
  const StockAdjustmentSaveResult({
    required this.stockAdjustmentId,
    required this.idempotentReplay,
  });

  final int stockAdjustmentId;
  final bool idempotentReplay;
}
