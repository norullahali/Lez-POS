import 'package:flutter/foundation.dart';

@immutable
class InvoiceHistoryRow {
  final int id;
  final String invoiceNumber;
  final DateTime saleDate;
  final String customerName;
  final String cashierName;
  final int itemCount;
  final double total;
  final String paymentMethod;
  final String status;

  const InvoiceHistoryRow({
    required this.id,
    required this.invoiceNumber,
    required this.saleDate,
    required this.customerName,
    required this.cashierName,
    required this.itemCount,
    required this.total,
    required this.paymentMethod,
    required this.status,
  });
}

@immutable
class InvoiceHistoryPage {
  final List<InvoiceHistoryRow> rows;
  final int totalCount;
  final int page;
  final int pageSize;

  const InvoiceHistoryPage({
    required this.rows,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  int get totalPages =>
      totalCount == 0 ? 1 : (totalCount + pageSize - 1) ~/ pageSize;
}

/// Maps raw [payment_method] DB codes to Arabic labels for the UI.
String invoicePaymentLabelAr(String code) {
  switch (code.toUpperCase()) {
    case 'CASH':
      return 'نقدي';
    case 'CARD':
      return 'بطاقة';
    case 'DEBT':
      return 'آجل';
    case 'MIXED':
      return 'مختلط';
    default:
      return code;
  }
}
