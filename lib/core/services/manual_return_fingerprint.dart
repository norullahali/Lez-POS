import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for a logical manual customer return (B10).
class ManualReturnFingerprint {
  ManualReturnFingerprint._();

  static double roundAmount(double amount) =>
      double.parse(amount.toStringAsFixed(6));

  static String normalizeReason(String? reason) => (reason ?? '').trim();

  static String compute({
    required int productId,
    required double quantity,
    required double unitPrice,
    required String reason,
    int? userId,
    int? approvedByUserId,
  }) {
    final payload = <String, dynamic>{
      'approvedByUserId': approvedByUserId,
      'productId': productId,
      'quantity': roundAmount(quantity),
      'reason': normalizeReason(reason),
      'unitPrice': roundAmount(unitPrice),
      'userId': userId,
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}
