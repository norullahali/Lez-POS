import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/report_metric_model.dart';
import '../../modules/shared/analytics_formatters.dart';
import '../../modules/shared/analytics_kpi_builder.dart';

class ReportMetricCard extends StatelessWidget {
  const ReportMetricCard({super.key, required this.metric});

  final ReportMetricModel metric;

  @override
  Widget build(BuildContext context) {
    final trend = metric.trendPercent;
    return Card(
      child: InkWell(
        onTap: metric.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(metric.icon, color: metric.color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metric.value,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    if (metric.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(metric.subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: metric.color)),
                    ],
                    if (trend != null) ...[
                      const SizedBox(height: 4),
                      _TrendBadge(percent: trend, semantic: metric.trendSemantic),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.percent, this.semantic});

  final double percent;
  final ReportTrendSemantic? semantic;

  @override
  Widget build(BuildContext context) {
    final resolved = semantic ?? AnalyticsKpi.growthSemantic(percent);
    final color = switch (resolved) {
      ReportTrendSemantic.positive => AppColors.success,
      ReportTrendSemantic.negative => AppColors.error,
      ReportTrendSemantic.warning => AppColors.warning,
      ReportTrendSemantic.neutral => AppColors.textSecondary,
    };
    final icon = switch (resolved) {
      ReportTrendSemantic.positive => Icons.arrow_upward_rounded,
      ReportTrendSemantic.negative => Icons.arrow_downward_rounded,
      ReportTrendSemantic.warning => Icons.warning_amber_rounded,
      ReportTrendSemantic.neutral => Icons.remove_rounded,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          AnalyticsFormatters.signedPercent(percent),
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}