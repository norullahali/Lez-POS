import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic settlement-intent hash for supplier refund UI idempotency (B29).
///
/// Mirrors [SupplierRefundSettlementService] parameter matching only; does not
/// replace backend replay logic.
class SupplierRefundSettlementIntentFingerprint {
  SupplierRefundSettlementIntentFingerprint._();

  /// Aligned with service idempotency tolerance.
  static const amountTolerance = 0.0001;

  static String compute({
    required int supplierId,
    required double amount,
    required int? returnId,
    required String? note,
  }) {
    final normalizedNote = (note ?? '').trim();
    final payload = <String, dynamic>{
      'supplierId': supplierId,
      'amount': _round(amount),
      'returnId': returnId,
      'note': normalizedNote,
    };
    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(6));
}
