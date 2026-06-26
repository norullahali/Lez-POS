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

  /// Reserved for Phase 8 time-series charts. No-op in Phase 5.
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

/// Time-series granularity reserved for Phase 8. No-op in Phase 5.
enum DashboardGranularity { day, week, month }