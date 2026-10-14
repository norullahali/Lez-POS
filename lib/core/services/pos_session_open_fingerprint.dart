import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for POS session open intent (B25).
class PosSessionOpenFingerprint {
  PosSessionOpenFingerprint._();

  static double roundOpeningCash(double amount) =>
      double.parse(amount.toStringAsFixed(6));

  static String compute({
    required double openingCash,
    int? createdByUserId,
  }) {
    final payload = <String, dynamic>{
      'openingCash': roundOpeningCash(openingCash),
      'createdByUserId': createdByUserId,
    };
    final json = jsonEncode(payload);
    return sha256.convert(utf8.encode(json)).toString();
  }
}
