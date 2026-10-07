// lib/core/services/opening_stock_product_already_opened_exception.dart

/// Thrown when opening stock is attempted for a product that already has a seal.
class OpeningStockProductAlreadyOpenedException implements Exception {
  const OpeningStockProductAlreadyOpenedException(this.productId, [
    this.message = 'product already has committed opening stock',
  ]);

  final int productId;
  final String message;

  @override
  String toString() => '$message (productId=$productId)';
}
