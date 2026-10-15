import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Deterministic settlement-intent hash for customer refund UI idempotency (B28).
///
/// Mirrors [CustomerRefundSettlementService] parameter matching only; does not
/// replace backend replay logic.
class CustomerRefundSettlementIntentFingerprint {
  CustomerRefundSettlementIntentFingerprint._();

  /// Aligned with service idempotency tolerance.
  static const amountTolerance = 0.0001;

  static String compute({
    required int customerId,
    required double amount,
    required int? returnId,
    required String? note,
  }) {
    final normalizedNote = (note ?? '').trim();
    final payload = <String, dynamic>{
      'customerId': customerId,
      'amount': _round(amount),
      'returnId': returnId,
      'note': normalizedNote,
    };
    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(6));
}
