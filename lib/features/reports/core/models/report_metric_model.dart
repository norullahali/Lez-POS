import 'package:flutter/material.dart';

/// Unified trend semantics for KPI cards across reports.
enum ReportTrendSemantic { positive, negative, neutral, warning }

class ReportMetricModel {
  const ReportMetricModel({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.trendPercent,
    this.trendSemantic,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final double? trendPercent;
  final ReportTrendSemantic? trendSemantic;
  final VoidCallback? onTap;
}