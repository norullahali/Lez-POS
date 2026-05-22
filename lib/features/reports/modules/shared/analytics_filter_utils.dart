import 'package:flutter/material.dart';

import '../../core/models/report_date_preset.dart';
import '../../core/models/report_filter_model.dart';
import 'advanced_analytics_models.dart';

ReportFilterModel comparativePresetFilter(ReportDatePreset preset) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return switch (preset) {
    ReportDatePreset.today => ReportFilterModel(
        preset: preset,
        range: DateTimeRange(start: today, end: today),
      ),
    ReportDatePreset.yesterday => ReportFilterModel(
        preset: preset,
        range: DateTimeRange(
          start: today.subtract(const Duration(days: 1)),
          end: today.subtract(const Duration(days: 1)),
        ),
      ),
    ReportDatePreset.thisWeek => ReportFilterModel(
        preset: preset,
        range: DateTimeRange(
          start: today.subtract(Duration(days: today.weekday - 1)),
          end: today,
        ),
      ),
    ReportDatePreset.thisMonth => ReportFilterModel(
        preset: preset,
        range: DateTimeRange(start: DateTime(now.year, now.month, 1), end: today),
      ),
    _ => ReportFilterModel(
        preset: ReportDatePreset.thisMonth,
        range: DateTimeRange(start: DateTime(now.year, now.month, 1), end: today),
      ),
  };
}

AnalyticsDateRange previousRangeFor(ReportFilterModel current) {
  final range = current.resolveRange();
  final days = range.end.difference(range.start).inDays + 1;
  final prevEnd = range.start.subtract(const Duration(days: 1));
  final prevStart = prevEnd.subtract(Duration(days: days - 1));
  return AnalyticsDateRange(from: prevStart, to: prevEnd);
}

/// Presets allowed for comparative analytics chips.
const comparativePresets = [
  ReportDatePreset.today,
  ReportDatePreset.yesterday,
  ReportDatePreset.thisWeek,
  ReportDatePreset.thisMonth,
];
