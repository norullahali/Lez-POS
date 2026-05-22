import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/report_filter_model.dart';
import '../models/report_tab_id.dart';
import 'report_session_provider.dart';

export 'report_session_provider.dart';
export 'report_session_state.dart';

/// Global filter accessor — delegates to [reportSessionProvider] (daily tab).
final reportFilterProvider = Provider<ReportFilterModel>((ref) {
  return ref.watch(reportSessionProvider.select((s) => s.filterFor(ReportTabId.daily)));
});

/// Debounced read for expensive range queries.
final debouncedReportFilterProvider = Provider.family<ReportFilterModel, ReportTabId>((ref, tab) {
  return ref.watch(reportSessionProvider.select((s) => s.filterFor(tab)));
});

/// Convenience helpers for tab filter updates.
extension ReportSessionFilterX on WidgetRef {
  ReportFilterModel reportFilter(ReportTabId tab) =>
      watch(reportSessionProvider.select((s) => s.filterFor(tab)));

  void updateReportFilter(ReportTabId tab, ReportFilterModel filter, {bool debounce = false}) {
    final notifier = read(reportSessionProvider.notifier);
    if (debounce) {
      notifier.updateFilterDebounced(tab, filter);
    } else {
      notifier.updateFilter(tab, filter);
    }
  }
}