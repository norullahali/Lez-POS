import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../features/pos/models/cart_item.dart';

/// Deterministic fingerprint for a logical POS checkout request (B5-F1).
class PosSaleFingerprint {
  PosSaleFingerprint._();

  static String compute({
    required int? sessionId,
    required int cartSlotId,
    required List<CartItem> items,
    required double invoiceDiscount,
    required double loyaltyPointsUsed,
    required double loyaltyDiscount,
    required int? customerId,
    required PaymentInfo payment,
    int? approvedByUserId,
  }) {
    final sortedItems = [...items]
      ..sort((a, b) => (a.product.id ?? 0).compareTo(b.product.id ?? 0));

    final payload = <String, dynamic>{
      'sessionId': sessionId,
      'cartSlotId': cartSlotId,
      'invoiceDiscount': _round(invoiceDiscount),
      'loyaltyPointsUsed': _round(loyaltyPointsUsed),
      'loyaltyDiscount': _round(loyaltyDiscount),
      'customerId': customerId,
      'payment': {
        'method': payment.method,
        'cashPaid': _round(payment.cashPaid),
        'cardPaid': _round(payment.cardPaid),
        'change': _round(payment.change),
        'debtAmount': _round(payment.debtAmount),
        'pointsUsed': _round(payment.pointsUsed),
        'loyaltyDiscount': _round(payment.loyaltyDiscount),
      },
      'approvedByUserId': approvedByUserId,
      'items': sortedItems
          .map(
            (item) => {
              'productId': item.product.id,
              'quantity': _round(item.effectiveQuantity),
              'unitPrice': _round(item.unitPrice),
              'discount': _round(item.discount),
            },
          )
          .toList(),
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(6));
}
