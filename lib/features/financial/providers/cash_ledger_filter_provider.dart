import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../reports/core/models/report_filter_model.dart';
import '../models/cash_ledger_event_type.dart';
import '../models/cash_ledger_filter.dart';

class CashLedgerFilterNotifier extends Notifier<CashLedgerFilter> {
  @override
  CashLedgerFilter build() => const CashLedgerFilter();

  void setDateFilter(ReportFilterModel filter) {
    state = state.copyWith(dateFilter: filter, page: 0);
  }

  void setEventType(CashLedgerEventType? type) {
    state = state.copyWith(
      eventType: type,
      clearEventType: type == null,
      page: 0,
    );
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query, page: 0);
  }

  void setPage(int page) {
    state = state.copyWith(page: page);
  }

  void resetFilters() {
    state = const CashLedgerFilter();
  }

  void refresh() {
    state = state.copyWith(page: state.page);
  }
}

final cashLedgerFilterProvider =
    NotifierProvider<CashLedgerFilterNotifier, CashLedgerFilter>(
  CashLedgerFilterNotifier.new,
);