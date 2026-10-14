import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for POS session close intent (B26).
class PosSessionCloseFingerprint {
  PosSessionCloseFingerprint._();

  static double roundClosingCash(double amount) =>
      double.parse(amount.toStringAsFixed(6));

  /// Empty or whitespace-only notes normalize to null.
  static String? normalizeNotes(String? notes) {
    if (notes == null) return null;
    final trimmed = notes.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String compute({
    required int sessionId,
    required double closingCash,
    String? notes,
    int? closedByUserId,
  }) {
    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'closingCash': roundClosingCash(closingCash),
      'notes': normalizeNotes(notes),
      'closedByUserId': closedByUserId,
    };
    final json = jsonEncode(payload);
    return sha256.convert(utf8.encode(json)).toString();
  }

  static String fromClosedSession({
    required int sessionId,
    required double closingCash,
    String? notes,
    int? closedByUserId,
  }) =>
      compute(
        sessionId: sessionId,
        closingCash: closingCash,
        notes: notes,
        closedByUserId: closedByUserId,
      );
}
