import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for a bulk opening stock save request (B20).
class OpeningStockSaveFingerprint {
  OpeningStockSaveFingerprint._();

  static const legacyBackfillKey = '__legacy_v47_backfill__';
  static const legacySystemCreatedBy = 0;

  static double roundQuantity(double value) =>
      double.parse(value.toStringAsFixed(6));

  static double roundUnitCost(double value) =>
      double.parse(value.toStringAsFixed(6));

  /// Validates and returns sorted normalized product rows for persistence.
  static List<OpeningStockFingerprintProduct> normalizeProducts(
    List<OpeningStockFingerprintProduct> products,
  ) {
    if (products.isEmpty) {
      throw ArgumentError('opening stock bulk must include at least one product');
    }

    final seen = <int>{};
    final normalized = <OpeningStockFingerprintProduct>[];
    for (final product in products) {
      if (product.productId <= 0) {
        throw ArgumentError('productId must be positive');
      }
      if (product.quantity <= 0) {
        throw ArgumentError('quantity must be positive');
      }
      if (product.unitCost < 0) {
        throw ArgumentError('unitCost must be non-negative');
      }
      if (!seen.add(product.productId)) {
        throw ArgumentError('duplicate productId in opening stock bulk');
      }
      normalized.add(
        OpeningStockFingerprintProduct(
          productId: product.productId,
          quantity: roundQuantity(product.quantity),
          unitCost: roundUnitCost(product.unitCost),
        ),
      );
    }

    normalized.sort((a, b) => a.productId.compareTo(b.productId));
    return normalized;
  }

  static String compute({
    required List<OpeningStockFingerprintProduct> products,
    required int createdBy,
  }) {
    if (createdBy <= 0) {
      throw ArgumentError('createdBy must be positive');
    }

    final normalized = normalizeProducts(products);
    final payload = <String, dynamic>{
      'products': normalized
          .map(
            (p) => <String, dynamic>{
              'productId': p.productId,
              'quantity': p.quantity,
              'unitCost': p.unitCost,
            },
          )
          .toList(),
      'createdBy': createdBy,
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}

class OpeningStockFingerprintProduct {
  const OpeningStockFingerprintProduct({
    required this.productId,
    required this.quantity,
    required this.unitCost,
  });

  final int productId;
  final double quantity;
  final double unitCost;
}
