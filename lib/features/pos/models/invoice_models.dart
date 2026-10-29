import 'dart:typed_data';

class InvoiceItem {
  final String name;
  final double qty;
  final double unitPrice;
  final double lineTotal;

  /// Per-line discount persisted at sale time (absolute amount).
  final double lineDiscount;

  InvoiceItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
    this.lineDiscount = 0,
  });
}

class InvoiceData {
  final double? paid;
  final double? change;
  final double? loyaltyPoints;
  final String invoiceNumber;
  final DateTime date;
  final List<InvoiceItem> items;
  /// Authoritative final invoice total from [sales_invoices.total].
  final double total;

  /// Persisted header subtotal (sum of line totals at sale). Null for synthetic/test receipts.
  final double? headerSubtotal;

  /// Combined invoice + loyalty discount from [sales_invoices.discount_amount].
  final double? headerDiscountTotal;

  final double? cashPaid;
  final double? cardPaid;
  final double? debtAmount;
  final String? paymentMethod;

  final String storeName;
  final String? phone;
  final String? address;
  final Uint8List? logoBytes;
  final String? customerName;
  final String? cashierName;
  /// Primary footer text (line 1).
  final String? footer;
  /// Optional second footer line, shown below [footer].
  final String? footer2;
  final bool showTax;
  /// Whether to print a QR code at the end of the receipt.
  final bool showQr;

  // -- Return metadata (null for non-returned invoices) ----------------------
  final bool isReturned;
  final DateTime? returnDate;
  final String? returnNote;
  final String? returnedByName;

  InvoiceData({
    this.paid,
    this.change,
    this.loyaltyPoints,
    required this.invoiceNumber,
    required this.items,
    required this.storeName,
    required this.total,
    this.headerSubtotal,
    this.headerDiscountTotal,
    this.cashPaid,
    this.cardPaid,
    this.debtAmount,
    this.paymentMethod,
    this.phone,
    this.address,
    this.logoBytes,
    this.customerName,
    this.cashierName,
    this.footer,
    this.footer2,
    this.showTax = true,
    this.showQr = false,
    this.isReturned = false,
    this.returnDate,
    this.returnNote,
    this.returnedByName,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}
