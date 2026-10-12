import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'expense_creation_fingerprint.dart';

/// Deterministic fingerprints for expense UPDATE and VOID (B22).
class ExpenseMutationFingerprint {
  ExpenseMutationFingerprint._();

  static const String operationUpdate = 'UPDATE';
  static const String operationVoid = 'VOID';

  static String computeUpdate({
    required int expenseId,
    required int categoryId,
    required double amount,
    required DateTime expenseDate,
    required DateTime paidAt,
    required String notes,
    required int updatedBy,
    int? sessionId,
  }) {
    if (updatedBy <= 0) {
      throw ArgumentError('updatedBy must be positive');
    }
    if (expenseId <= 0) {
      throw ArgumentError('expenseId must be positive');
    }

    final payload = <String, dynamic>{
      'operation': operationUpdate,
      'expenseId': expenseId,
      'categoryId': categoryId,
      'amount': ExpenseCreationFingerprint.roundAmount(amount),
      'expenseDate': ExpenseCreationFingerprint.dateString(expenseDate),
      'paidAt': ExpenseCreationFingerprint.dateString(paidAt),
      'notes': ExpenseCreationFingerprint.normalizeNotes(notes),
      'sessionId': sessionId,
      'updatedBy': updatedBy,
    };

    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  static String computeVoid({
    required int expenseId,
    required int voidedBy,
  }) {
    if (voidedBy <= 0) {
      throw ArgumentError('voidedBy must be positive');
    }
    if (expenseId <= 0) {
      throw ArgumentError('expenseId must be positive');
    }

    final payload = <String, dynamic>{
      'operation': operationVoid,
      'expenseId': expenseId,
      'voidedBy': voidedBy,
    };

    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }
}
