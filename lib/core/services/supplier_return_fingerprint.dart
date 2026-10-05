import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'supplier_return_service.dart';

/// Deterministic fingerprint for a logical purchase-linked supplier return (B15).
class SupplierReturnFingerprint {
  SupplierReturnFingerprint._();

  static double roundQuantity(double quantity) =>
      double.parse(quantity.toStringAsFixed(6));

  static String normalizeText(String? value) => (value ?? '').trim();

  static String compute(SupplierReturnPostingInput input) {
    final aggregated = aggregatePostingLines(input.lines);
    final sortedEntries = aggregated.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final lines = sortedEntries
        .map(
          (entry) => {
            'purchaseItemId': entry.key,
            'quantity': roundQuantity(entry.value),
          },
        )
        .toList();

    final payload = <String, dynamic>{
      'lines': lines,
      'notes': normalizeText(input.notes),
      'purchaseInvoiceId': input.purchaseInvoiceId,
      'reason': normalizeText(input.reason),
      'supplierId': input.supplierId,
    };

    if (input.returnDate != null) {
      payload['returnDate'] = _dateString(input.returnDate!);
    }

    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static String _dateString(DateTime value) {
    final local = DateTime(value.year, value.month, value.day);
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
