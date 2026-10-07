// lib/core/services/opening_stock_live_activity_exception.dart

/// Thrown when opening stock is attempted for a product with live inventory
/// activity beyond OPENING ledger rows.
class OpeningStockLiveActivityException implements Exception {
  const OpeningStockLiveActivityException(this.productId, [
    this.message =
        'product already has inventory activity and cannot receive opening stock',
  ]);

  final int productId;
  final String message;

  @override
  String toString() => '$message (productId=$productId)';
}
