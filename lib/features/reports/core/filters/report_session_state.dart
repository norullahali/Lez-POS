import 'package:flutter/material.dart';
import '../models/report_date_preset.dart';
import '../models/report_filter_model.dart';
import '../models/report_tab_id.dart';

class ReportSessionState {
  const ReportSessionState({
    this.activeTabIndex = 0,
    this.filters = const {},
  });

  final int activeTabIndex;
  final Map<ReportTabId, ReportFilterModel> filters;

  ReportFilterModel filterFor(ReportTabId tab) => filters[tab] ?? _defaultFilter(tab);

  ReportSessionState copyWith({
    int? activeTabIndex,
    Map<ReportTabId, ReportFilterModel>? filters,
  }) {
    return ReportSessionState(
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      filters: filters ?? this.filters,
    );
  }

  static ReportFilterModel _defaultFilter(ReportTabId tab) {
    final now = DateTime.now();
    final monthRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    return switch (tab) {
      ReportTabId.daily => ReportFilterModel(preset: ReportDatePreset.today),
      ReportTabId.monthly => ReportFilterModel(
          preset: ReportDatePreset.thisYear,
          year: now.year,
        ),
      ReportTabId.topProducts ||
      ReportTabId.purchases ||
      ReportTabId.profitAnalysis ||
      ReportTabId.cashFlow ||
      ReportTabId.returnImpact ||
      ReportTabId.inventoryMovement ||
      ReportTabId.taxReports ||
      ReportTabId.employeePerformance ||
      ReportTabId.hourlyHeatmap ||
      ReportTabId.categoryPerformance ||
      ReportTabId.productVelocity ||
      ReportTabId.executiveDashboard ||
      ReportTabId.comparativeAnalytics =>
        ReportFilterModel(preset: ReportDatePreset.thisMonth, range: monthRange),
      _ => const ReportFilterModel(),
    };
  }
}