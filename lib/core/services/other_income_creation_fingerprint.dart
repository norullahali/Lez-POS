import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic fingerprint for a logical other income creation request (B19).
class OtherIncomeCreationFingerprint {
  OtherIncomeCreationFingerprint._();

  static double roundAmount(double amount) =>
      double.parse(amount.toStringAsFixed(6));

  static String normalizeNotes(String? notes) => (notes ?? '').trim();

  /// Local date-only midnight for persistence and fingerprinting.
  static DateTime normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String dateString(DateTime value) {
    final local = normalizeDate(value);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String compute({
    required int categoryId,
    required double amount,
    required DateTime incomeDate,
    required DateTime receivedAt,
    required String notes,
    required int createdBy,
    int? sessionId,
  }) {
    final payload = <String, dynamic>{
      'categoryId': categoryId,
      'amount': roundAmount(amount),
      'incomeDate': dateString(incomeDate),
      'receivedAt': dateString(receivedAt),
      'notes': normalizeNotes(notes),
      'sessionId': sessionId,
      'createdBy': createdBy,
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}