// lib/core/services/opening_stock_save_idempotency_conflict_exception.dart

/// Thrown when the same opening stock idempotency key is reused with a
/// different bulk fingerprint.
class OpeningStockSaveIdempotencyConflictException implements Exception {
  const OpeningStockSaveIdempotencyConflictException([
    this.message =
        'idempotency key reused with different opening stock parameters',
  ]);

  final String message;

  @override
  String toString() => message;
}
