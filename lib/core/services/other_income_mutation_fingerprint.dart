import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'other_income_creation_fingerprint.dart';

/// Deterministic fingerprints for other income UPDATE and VOID (B23).
class OtherIncomeMutationFingerprint {
  OtherIncomeMutationFingerprint._();

  static const String operationUpdate = 'UPDATE';
  static const String operationVoid = 'VOID';

  static String computeUpdate({
    required int otherIncomeRecordId,
    required int categoryId,
    required double amount,
    required DateTime incomeDate,
    required DateTime receivedAt,
    required String notes,
    required int updatedBy,
    int? sessionId,
  }) {
    if (updatedBy <= 0) {
      throw ArgumentError('updatedBy must be positive');
    }
    if (otherIncomeRecordId <= 0) {
      throw ArgumentError('otherIncomeRecordId must be positive');
    }

    final payload = <String, dynamic>{
      'operation': operationUpdate,
      'otherIncomeRecordId': otherIncomeRecordId,
      'categoryId': categoryId,
      'amount': OtherIncomeCreationFingerprint.roundAmount(amount),
      'incomeDate': OtherIncomeCreationFingerprint.dateString(incomeDate),
      'receivedAt': OtherIncomeCreationFingerprint.dateString(receivedAt),
      'notes': OtherIncomeCreationFingerprint.normalizeNotes(notes),
      'sessionId': sessionId,
      'updatedBy': updatedBy,
    };

    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  static String computeVoid({
    required int otherIncomeRecordId,
    required int voidedBy,
  }) {
    if (voidedBy <= 0) {
      throw ArgumentError('voidedBy must be positive');
    }
    if (otherIncomeRecordId <= 0) {
      throw ArgumentError('otherIncomeRecordId must be positive');
    }

    final payload = <String, dynamic>{
      'operation': operationVoid,
      'otherIncomeRecordId': otherIncomeRecordId,
      'voidedBy': voidedBy,
    };

    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }
}
