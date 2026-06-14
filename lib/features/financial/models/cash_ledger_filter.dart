import 'package:flutter/material.dart';

import '../../reports/core/models/report_date_preset.dart';
import '../../reports/core/models/report_filter_model.dart';
import 'cash_ledger_event_type.dart';

/// Filter state for Cash Ledger v1 queries.
class CashLedgerFilter {
  const CashLedgerFilter({
    this.dateFilter = const ReportFilterModel(preset: ReportDatePreset.thisMonth),
    this.eventType,
    this.searchQuery = '',
    this.page = 0,
    this.pageSize = 50,
    this.sortDescending = true,
  });

  final ReportFilterModel dateFilter;
  final CashLedgerEventType? eventType;
  final String searchQuery;
  final int page;
  final int pageSize;
  final bool sortDescending;

  DateTimeRange get resolvedRange => dateFilter.resolveRange();

  CashLedgerFilter copyWith({
    ReportFilterModel? dateFilter,
    CashLedgerEventType? eventType,
    String? searchQuery,
    int? page,
    int? pageSize,
    bool? sortDescending,
    bool clearEventType = false,
  }) {
    return CashLedgerFilter(
      dateFilter: dateFilter ?? this.dateFilter,
      eventType: clearEventType ? null : (eventType ?? this.eventType),
      searchQuery: searchQuery ?? this.searchQuery,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      sortDescending: sortDescending ?? this.sortDescending,
    );
  }
}