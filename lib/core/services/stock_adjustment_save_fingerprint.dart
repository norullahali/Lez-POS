import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for a stock adjustment save request (B21).
class StockAdjustmentSaveFingerprint {
  StockAdjustmentSaveFingerprint._();

  static double roundQuantity(double value) =>
      double.parse(value.toStringAsFixed(6));

  static String normalizeReason(String? reason) => (reason ?? '').trim();

  static String normalizeNote(String? note) => (note ?? '').trim();

  static String compute({
    required int productId,
    required double quantityChange,
    required String adjustmentType,
    required String reason,
    required String note,
    required int createdBy,
  }) {
    if (createdBy <= 0) {
      throw ArgumentError('createdBy must be positive');
    }
    if (productId <= 0) {
      throw ArgumentError('productId must be positive');
    }

    final payload = <String, dynamic>{
      'productId': productId,
      'quantityChange': roundQuantity(quantityChange),
      'adjustmentType': adjustmentType,
      'reason': normalizeReason(reason),
      'note': normalizeNote(note),
      'createdBy': createdBy,
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}
