import 'package:flutter/material.dart';

enum ReportChartType { line, bar, pie, trend }

class ReportChartPoint {
  const ReportChartPoint({required this.label, required this.value, this.secondaryValue});
  final String label;
  final double value;
  final double? secondaryValue;
}

class ReportChartSeries {
  const ReportChartSeries({
    required this.id,
    required this.label,
    required this.points,
    required this.color,
  });

  final String id;
  final String label;
  final List<ReportChartPoint> points;
  final Color color;
}

class ReportChartConfig {
  const ReportChartConfig({
    required this.title,
    required this.type,
    required this.series,
    this.secondarySeries,
    this.yAxisFormatter,
    this.emptyMessage = 'لا توجد بيانات للعرض',
    this.animationDuration = const Duration(milliseconds: 400),
    this.onPointTap,
    this.selectedPointIndex,
  });

  final String title;
  final ReportChartType type;
  final List<ReportChartSeries> series;
  final ReportChartSeries? secondarySeries;
  final String Function(double value)? yAxisFormatter;
  final String emptyMessage;
  final Duration animationDuration;

  /// Tap callback — bar and pie charts invoke on [FlTapUpEvent] only (not hover).
  final void Function(ReportChartPoint point, String seriesId)? onPointTap;

  /// Optional presentation-only highlight index (bar group / pie slice).
  /// Does not alter chart data — used by interactive dashboards.
  final int? selectedPointIndex;
}