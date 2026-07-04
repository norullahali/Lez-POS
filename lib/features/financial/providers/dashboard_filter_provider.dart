import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../reports/core/models/report_date_preset.dart";
import "../../reports/core/models/report_filter_model.dart";
import "../models/dashboard_filter.dart";

/// Dashboard-specific filter notifier -- independent of cashLedgerFilterProvider.
class DashboardFilterNotifier extends Notifier<DashboardFilter> {
  @override
  DashboardFilter build() => const DashboardFilter();

  void setDateFilter(ReportFilterModel filter) {
    state = state.copyWith(dateFilter: filter);
  }

  void setPreset(ReportDatePreset preset) {
    state = state.copyWith(
      dateFilter: ReportFilterModel(preset: preset),
    );
  }

  /// Updates [DashboardFilter.granularity] for future manual chart-bucket UI.
  ///
  /// **Not consumed yet** — [dashboardCashAnalyticsProvider] auto-resolves
  /// granularity from the date range. Safe to call; no runtime chart effect today.
  void setGranularity(DashboardGranularity granularity) {
    state = state.copyWith(granularity: granularity);
  }

  void reset() => state = const DashboardFilter();
}

final dashboardFilterProvider =
    NotifierProvider<DashboardFilterNotifier, DashboardFilter>(
  DashboardFilterNotifier.new,
);