import 'dart:typed_data';

class InvoiceItem {
  final String name;
  final double qty;
  final double unitPrice;
  final double lineTotal;

  InvoiceItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });
}

class InvoiceData {
  final double? paid;
  final double? change;
  final double? loyaltyPoints;
  final String invoiceNumber;
  final DateTime date;
  final List<InvoiceItem> items;
  final double total;
  final String storeName;
  final String? phone;
  final String? address;
  final Uint8List? logoBytes;
  final String? customerName;
  final String? cashierName;
  final String? footer;
  final bool showTax;

  InvoiceData({
    this.paid,
    this.change,
    this.loyaltyPoints,
    required this.invoiceNumber,
    required this.items,
    required this.storeName,
    required this.total,
    this.phone,
    this.address,
    this.logoBytes,
    this.customerName,
    this.cashierName,
    this.footer,
    this.showTax = true,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}
