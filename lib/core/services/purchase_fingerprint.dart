import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One logical purchase line for fingerprinting (B7).
class PurchaseFingerprintLine {
  const PurchaseFingerprintLine({
    required this.productId,
    required this.quantity,
    required this.unitCost,
    this.discountAmount = 0,
    this.expiryDate,
  });

  final int productId;
  final double quantity;
  final double unitCost;
  final double discountAmount;
  final DateTime? expiryDate;
}

/// Deterministic fingerprint for a logical purchase save request (B7).
class PurchaseFingerprint {
  PurchaseFingerprint._();

  static String compute({
    required int? supplierId,
    required String? operatorInvoiceNumber,
    required DateTime purchaseDate,
    required double invoiceDiscount,
    required double total,
    required double paidAmount,
    required DateTime? dueDate,
    required String notes,
    required List<PurchaseFingerprintLine> items,
  }) {
    final canonicalItems = _canonicalizeItems(items);

    final payload = <String, dynamic>{
      'supplierId': supplierId,
      'operatorInvoiceNumber': _normalizeOptionalText(operatorInvoiceNumber),
      'purchaseDate': _dateString(purchaseDate),
      'invoiceDiscount': _round(invoiceDiscount),
      'total': _round(total),
      'paidAmount': _round(paidAmount),
      'dueDate': dueDate == null ? null : _dateString(dueDate),
      'notes': notes.trim(),
      'items': canonicalItems
          .map(
            (item) => {
              'productId': item.productId,
              'quantity': _round(item.quantity),
              'unitCost': _round(item.unitCost),
              'discountAmount': _round(item.discountAmount),
              'expiryDate': item.expiryDate == null
                  ? null
                  : _dateString(item.expiryDate!),
            },
          )
          .toList(),
    };

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static List<PurchaseFingerprintLine> _canonicalizeItems(
    List<PurchaseFingerprintLine> items,
  ) {
    final merged = <String, PurchaseFingerprintLine>{};

    for (final item in items) {
      final expiryKey =
          item.expiryDate == null ? '' : _dateString(item.expiryDate!);
      final key =
          '${item.productId}|${_round(item.unitCost)}|${_round(item.discountAmount)}|$expiryKey';

      final existing = merged[key];
      if (existing == null) {
        merged[key] = item;
      } else {
        merged[key] = PurchaseFingerprintLine(
          productId: item.productId,
          quantity: existing.quantity + item.quantity,
          unitCost: item.unitCost,
          discountAmount: item.discountAmount,
          expiryDate: item.expiryDate,
        );
      }
    }

    final result = merged.values.toList()
      ..sort((a, b) {
        final byProduct = a.productId.compareTo(b.productId);
        if (byProduct != 0) return byProduct;
        final byCost = _round(a.unitCost).compareTo(_round(b.unitCost));
        if (byCost != 0) return byCost;
        final aExpiry = a.expiryDate;
        final bExpiry = b.expiryDate;
        if (aExpiry == null && bExpiry == null) return 0;
        if (aExpiry == null) return 1;
        if (bExpiry == null) return -1;
        return aExpiry.compareTo(bExpiry);
      });

    return result;
  }

  static String? _normalizeOptionalText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _dateString(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(6));
}
