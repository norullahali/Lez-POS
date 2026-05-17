import 'package:flutter/foundation.dart';

import '../../../core/constants/invoice_lifecycle.dart';

@immutable
class InvoiceDetailHeader {
  final int id;
  final String invoiceNumber;
  final DateTime saleDate;
  final String customerName;
  final String cashierName;
  final String paymentMethod;
  /// `completed` | `returned` — see [InvoiceLifecycleStatus].
  final String invoiceStatus;
  final double subtotal;
  final double discountTotal;
  final double total;
  final double cashPaid;
  final double cardPaid;
  final double changeAmount;

  const InvoiceDetailHeader({
    required this.id,
    required this.invoiceNumber,
    required this.saleDate,
    required this.customerName,
    required this.cashierName,
    required this.paymentMethod,
    required this.invoiceStatus,
    required this.subtotal,
    required this.discountTotal,
    required this.total,
    required this.cashPaid,
    required this.cardPaid,
    required this.changeAmount,
  });
}

@immutable
class InvoiceDetailLine {
  final String productName;
  final double quantity;
  final double unitPrice;
  final double discount;
  final double lineTotal;

  const InvoiceDetailLine({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.lineTotal,
  });
}

@immutable
class InvoiceDetailData {
  final InvoiceDetailHeader header;
  final List<InvoiceDetailLine> lines;
  final bool showTax;

  const InvoiceDetailData({
    required this.header,
    required this.lines,
    required this.showTax,
  });

  /// Net after invoice-level discounts (subtotal − discount), before tax line.
  double get netBeforeTax => (header.subtotal - header.discountTotal).clamp(0.0, double.infinity);

  double get taxAmount => showTax ? netBeforeTax * 0.15 : 0.0;

  /// Grand total shown: authoritative value from DB ([header.total]).
  double get grandTotal => header.total;

  bool get isReturned => invoiceIsReturned(header.invoiceStatus);
}
