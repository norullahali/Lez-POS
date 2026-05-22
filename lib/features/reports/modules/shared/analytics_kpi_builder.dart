import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../core/models/report_metric_model.dart';
import 'analytics_formatters.dart';

/// Standard KPI semantics for unified analytics cards.
class AnalyticsKpi {
  AnalyticsKpi._();

  static ReportTrendSemantic growthSemantic(double changePercent, {bool invert = false}) {
    if (changePercent.abs() < 0.5) return ReportTrendSemantic.neutral;
    final good = invert ? changePercent < 0 : changePercent > 0;
    return good ? ReportTrendSemantic.positive : ReportTrendSemantic.negative;
  }

  static ReportMetricModel currency({
    required String title,
    required double value,
    required IconData icon,
    Color? color,
    double? trendPercent,
    ReportTrendSemantic? trendSemantic,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return ReportMetricModel(
      title: title,
      value: AnalyticsFormatters.money(value),
      icon: icon,
      color: color ?? AppColors.primary,
      subtitle: subtitle,
      trendPercent: trendPercent,
      trendSemantic: trendSemantic ?? (trendPercent != null ? growthSemantic(trendPercent) : null),
      onTap: onTap,
    );
  }

  static ReportMetricModel percent({
    required String title,
    required double value,
    required IconData icon,
    Color? color,
    double? trendPercent,
    ReportTrendSemantic? trendSemantic,
    bool invertTrend = false,
    String? subtitle,
  }) {
    return ReportMetricModel(
      title: title,
      value: AnalyticsFormatters.pct(value),
      icon: icon,
      color: color ?? AppColors.accent,
      subtitle: subtitle,
      trendPercent: trendPercent,
      trendSemantic: trendSemantic ??
          (trendPercent != null ? growthSemantic(trendPercent, invert: invertTrend) : null),
    );
  }

  static ReportMetricModel count({
    required String title,
    required num value,
    required IconData icon,
    Color? color,
    String? subtitle,
    double? trendPercent,
    ReportTrendSemantic? trendSemantic,
  }) {
    return ReportMetricModel(
      title: title,
      value: AnalyticsFormatters.qty(value),
      icon: icon,
      color: color ?? AppColors.info,
      subtitle: subtitle,
      trendPercent: trendPercent,
      trendSemantic: trendSemantic,
    );
  }

  static ReportMetricModel text({
    required String title,
    required String? value,
    required IconData icon,
    Color? color,
    String? subtitle,
  }) {
    return ReportMetricModel(
      title: title,
      value: AnalyticsFormatters.label(value),
      icon: icon,
      color: color ?? AppColors.primary,
      subtitle: subtitle,
    );
  }

  static ReportMetricModel warning({
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
  }) {
    return ReportMetricModel(
      title: title,
      value: value,
      icon: icon,
      color: AppColors.warning,
      subtitle: subtitle,
      trendSemantic: ReportTrendSemantic.warning,
    );
  }
}
