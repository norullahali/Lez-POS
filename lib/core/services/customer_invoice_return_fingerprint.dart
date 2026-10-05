import 'dart:convert';

import 'package:crypto/crypto.dart';

enum CustomerInvoiceReturnFingerprintType {
  partial('partial'),
  full('full');

  const CustomerInvoiceReturnFingerprintType(this.code);
  final String code;
}

class CustomerInvoicePartialReturnLineInput {
  const CustomerInvoicePartialReturnLineInput({
    required this.saleItemId,
    required this.quantity,
  });

  final int saleItemId;
  final double quantity;
}

Map<int, double> aggregatePartialReturnLines(
  List<CustomerInvoicePartialReturnLineInput> lines,
) {
  final aggregated = <int, double>{};
  for (final line in lines) {
    aggregated[line.saleItemId] =
        (aggregated[line.saleItemId] ?? 0) + line.quantity;
  }
  return aggregated;
}

/// Deterministic fingerprint for invoice-linked customer returns (B16).
class CustomerInvoiceReturnFingerprint {
  CustomerInvoiceReturnFingerprint._();

  static double roundQuantity(double quantity) =>
      double.parse(quantity.toStringAsFixed(6));

  static String normalizeText(String? value) => (value ?? '').trim();

  static String computePartial({
    required int? customerId,
    required int saleInvoiceId,
    required List<CustomerInvoicePartialReturnLineInput> lines,
    String? note,
  }) {
    final aggregated = aggregatePartialReturnLines(lines);
    final sortedEntries = aggregated.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final payload = <String, dynamic>{
      'customerId': customerId,
      'lines': sortedEntries
          .map(
            (entry) => {
              'quantity': roundQuantity(entry.value),
              'saleItemId': entry.key,
            },
          )
          .toList(),
      'note': normalizeText(note),
      'returnType': CustomerInvoiceReturnFingerprintType.partial.code,
      'saleInvoiceId': saleInvoiceId,
    };

    return _hash(payload);
  }

  static String computeFull({
    required int? customerId,
    required int saleInvoiceId,
    String? note,
  }) {
    final payload = <String, dynamic>{
      'customerId': customerId,
      'note': normalizeText(note),
      'returnType': CustomerInvoiceReturnFingerprintType.full.code,
      'saleInvoiceId': saleInvoiceId,
    };

    return _hash(payload);
  }

  static String _hash(Map<String, dynamic> payload) {
    final canonical = jsonEncode(payload);
    return sha256.convert(utf8.encode(canonical)).toString();
  }
}