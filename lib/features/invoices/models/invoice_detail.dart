import 'package:flutter/foundation.dart';

import '../../../core/constants/invoice_lifecycle.dart';

/// Metadata stored when an invoice is fully returned.
/// All fields are nullable for backward compatibility with pre-v21 returns.
@immutable
class ReturnMetadata {
  final DateTime? returnDate;
  final String? returnNote;
  /// Display name of the user who performed the return.
  final String? returnedByName;

  const ReturnMetadata({
    this.returnDate,
    this.returnNote,
    this.returnedByName,
  });

  bool get hasData =>
      returnDate != null ||
      (returnNote != null && returnNote!.trim().isNotEmpty) ||
      (returnedByName != null && returnedByName!.trim().isNotEmpty);
}

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
  /// Non-null when [invoiceStatus] == `returned`.
  final ReturnMetadata? returnMetadata;

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
    this.returnMetadata,
  });
}

@immutable
class InvoiceDetailLine {
  /// sale_items.id — required for partial return lookups.
  final int id;
  /// sale_items.product_id — required for stock restoration.
  final int productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  /// Snapshot cost at time of sale — used for ledger valuation on return.
  final double unitCost;
  final double discount;
  final double lineTotal;

  const InvoiceDetailLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.unitCost = 0.0,
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

  ReturnMetadata? get returnMetadata => header.returnMetadata;
}
