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
  });

  final String title;
  final ReportChartType type;
  final List<ReportChartSeries> series;
  final ReportChartSeries? secondarySeries;
  final String Function(double value)? yAxisFormatter;
  final String emptyMessage;
  final Duration animationDuration;
  final void Function(ReportChartPoint point, String seriesId)? onPointTap;
}