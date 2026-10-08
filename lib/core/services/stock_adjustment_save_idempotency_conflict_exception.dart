// lib/core/services/stock_adjustment_save_idempotency_conflict_exception.dart

/// Thrown when the same idempotency key is reused with a different fingerprint (B21).
class StockAdjustmentSaveIdempotencyConflictException implements Exception {
  const StockAdjustmentSaveIdempotencyConflictException();

  @override
  String toString() =>
      'Stock adjustment save idempotency conflict: key reused with different payload';
}
