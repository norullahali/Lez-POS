import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for a logical supplier payment request (B8).
class SupplierPaymentFingerprint {
  SupplierPaymentFingerprint._();

  /// Canonical note for fingerprinting and payment persistence.
  static String normalizeNote(String? note) {
    final trimmed = (note ?? '').trim();
    return trimmed.isEmpty ? 'Payment to supplier' : trimmed;
  }

  /// Round monetary values to six decimal places (B7 precedent).
  static double roundAmount(double amount) =>
      double.parse(amount.toStringAsFixed(6));

  static String compute({
    required int supplierId,
    required double amount,
    required String note,
  }) {
    final payload = <String, dynamic>{
      'amount': roundAmount(amount),
      'note': normalizeNote(note),
      'supplierId': supplierId,
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}
