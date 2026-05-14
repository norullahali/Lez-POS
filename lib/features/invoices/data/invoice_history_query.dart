import 'package:flutter/foundation.dart';

/// Server-side filters + pagination for invoice history list.
@immutable
class InvoiceHistoryQuery {
  final String search;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? cashierName;
  final String? paymentMethod;
  final int page;
  final int pageSize;

  const InvoiceHistoryQuery({
    this.search = '',
    this.dateFrom,
    this.dateTo,
    this.cashierName,
    this.paymentMethod,
    this.page = 0,
    this.pageSize = 50,
  });

  InvoiceHistoryQuery copyWith({
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDateRange = false,
    String? cashierName,
    bool clearCashier = false,
    String? paymentMethod,
    bool clearPayment = false,
    int? page,
    int? pageSize,
  }) {
    return InvoiceHistoryQuery(
      search: search ?? this.search,
      dateFrom: clearDateRange ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateRange ? null : (dateTo ?? this.dateTo),
      cashierName: clearCashier ? null : (cashierName ?? this.cashierName),
      paymentMethod: clearPayment ? null : (paymentMethod ?? this.paymentMethod),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}
