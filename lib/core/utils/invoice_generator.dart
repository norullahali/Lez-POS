/// Generates structured invoice payloads for business/output layers.
///
/// This utility is intentionally UI-agnostic and returns plain data objects.
class InvoiceGenerator {
  /// Builds normalized invoice data.
  ///
  /// This will be used later for printing/PDF generation.
  /// Keep logic clean and extendable so future output formats can reuse
  /// the same structured payload without UI dependencies.
  Map<String, dynamic> generateInvoiceData({
    required String invoiceNumber,
    required DateTime date,
    required String cashierName,
    required List<Map<String, dynamic>> items,
    double? total,
    double? paid,
    double? remaining,
    String? customerName,
    int? loyaltyPoints,
  }) {
    final computedTotal = total ?? _calculateTotalFromItems(items);
    final computedPaid = paid ?? 0.0;
    final computedRemaining = remaining ?? (computedTotal - computedPaid);

    return <String, dynamic>{
      'invoiceNumber': invoiceNumber,
      'date': date,
      'cashierName': cashierName,
      'items': items,
      'total': computedTotal,
      'paid': computedPaid,
      'remaining': computedRemaining,
      'customerName': customerName,
      'loyaltyPoints': loyaltyPoints,
    };
  }

  double _calculateTotalFromItems(List<Map<String, dynamic>> items) {
    double sum = 0.0;

    for (final item in items) {
      final directTotal = item['total'];
      if (directTotal is num) {
        sum += directTotal.toDouble();
        continue;
      }

      final qty = item['quantity'];
      final price = item['unitPrice'];
      if (qty is num && price is num) {
        sum += qty.toDouble() * price.toDouble();
      }
    }

    return sum;
  }
}