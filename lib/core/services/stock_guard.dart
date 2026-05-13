import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

class InsufficientStockException implements Exception {
  final int productId;
  final String productName;
  final double currentStock;
  final double requestedQty;

  const InsufficientStockException({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.requestedQty,
  });

  double get shortfall => requestedQty - currentStock;

  String get localizedMessage => 'المخزون غير كافٍ: $productName\n'
      'المتوفر: ${currentStock.toStringAsFixed(0)} | '
      'المطلوب: ${requestedQty.toStringAsFixed(0)}';

  @override
  String toString() => localizedMessage;
}

bool canDeductStock({
  required double currentStock,
  required double quantity,
}) {
  return currentStock >= quantity;
}

class StockGuard {
  StockGuard._();

  static Future<void> deductStock({
    required AppDatabase db,
    required int productId,
    required double quantity,
    String? productName,
  }) async {
    if (quantity <= 0) {
      debugPrint(
        '[StockGuard] skip — productId=$productId qty=$quantity',
      );
      return;
    }

    final affected = await db.customUpdate(
      '''
      UPDATE products
      SET current_stock = current_stock - ?
      WHERE id = ? AND current_stock >= ?
      ''',
      variables: [
        Variable.withReal(quantity),
        Variable.withInt(productId),
        Variable.withReal(quantity),
      ],
      updates: {db.products},
    );

    if (affected == 0) {
      final actualStock = await db.stockDao.getStock(productId);

      throw InsufficientStockException(
        productId: productId,
        productName: productName ?? 'product #$productId',
        currentStock: actualStock,
        requestedQty: quantity,
      );
    }

    debugPrint(
      '[StockGuard] deducted=$quantity productId=$productId',
    );
  }
}
