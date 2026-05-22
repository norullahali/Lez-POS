import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/report_filter_model.dart';
import '../models/report_tab_id.dart';
import '../services/report_query_cache.dart';
import 'report_session_state.dart';

class ReportSessionNotifier extends StateNotifier<ReportSessionState> {
  ReportSessionNotifier() : super(const ReportSessionState());

  Timer? _debounce;

  void setActiveTab(int index) {
    if (index == state.activeTabIndex) return;
    state = state.copyWith(activeTabIndex: index);
  }

  void updateFilter(ReportTabId tab, ReportFilterModel filter) {
    ReportQueryCache.invalidatePrefix(tab.cachePrefix);
    state = state.copyWith(filters: {...state.filters, tab: filter});
  }

  void updateFilterDebounced(ReportTabId tab, ReportFilterModel filter) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      updateFilter(tab, filter);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final reportSessionProvider =
    StateNotifierProvider<ReportSessionNotifier, ReportSessionState>((ref) {
  return ReportSessionNotifier();
});