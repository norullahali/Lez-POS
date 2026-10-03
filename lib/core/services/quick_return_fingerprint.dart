import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for a logical quick return request (B9).
class QuickReturnFingerprint {
  QuickReturnFingerprint._();

  /// Round monetary/quantity values to six decimal places (B7/B8 precedent).
  static double roundAmount(double amount) =>
      double.parse(amount.toStringAsFixed(6));

  static String normalizeReason(String? reason) => (reason ?? '').trim();

  static String compute({
    required int productId,
    required double quantity,
    required double refundAmount,
    required String reason,
    required int userId,
    int? approvedByUserId,
  }) {
    final payload = <String, dynamic>{
      'approvedByUserId': approvedByUserId,
      'productId': productId,
      'quantity': roundAmount(quantity),
      'reason': normalizeReason(reason),
      'refundAmount': roundAmount(refundAmount),
      'userId': userId,
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}
