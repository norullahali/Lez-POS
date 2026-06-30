import "package:flutter/material.dart";

import "../../reports/core/models/report_date_preset.dart";
import "../../reports/core/models/report_filter_model.dart";

/// Filter state for the Financial Dashboard.
/// Simpler than CashLedgerFilter -- no event type or search.
class DashboardFilter {
  const DashboardFilter({
    this.dateFilter = const ReportFilterModel(preset: ReportDatePreset.thisMonth),
    this.granularity = DashboardGranularity.month,
  });

  final ReportFilterModel dateFilter;

  /// Reserved for Phase 5.3.3 manual chart bucket control.
  ///
  /// **Not read at runtime in Phase 5.3.1.** [dashboardCashAnalyticsProvider]
  /// always auto-resolves granularity from [resolvedRange] duration. This field
  /// exists so future UI can persist a user override without a filter-model migration.
  final DashboardGranularity granularity;

  DateTimeRange get resolvedRange => dateFilter.resolveRange();

  DashboardFilter copyWith({
    ReportFilterModel? dateFilter,
    DashboardGranularity? granularity,
  }) {
    return DashboardFilter(
      dateFilter: dateFilter ?? this.dateFilter,
      granularity: granularity ?? this.granularity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardFilter &&
          runtimeType == other.runtimeType &&
          dateFilter == other.dateFilter &&
          granularity == other.granularity;

  @override
  int get hashCode => Object.hash(dateFilter, granularity);
}

/// Time-series bucket granularity for Financial Dashboard cash-flow charts.
///
/// Phase 5.3.1: auto-selected in [dashboardCashAnalyticsProvider] from range
/// duration only. [DashboardFilter.granularity] is reserved, not consumed.
enum DashboardGranularity { day, week, month }