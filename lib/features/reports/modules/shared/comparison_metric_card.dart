import 'package:flutter/material.dart';

import 'analytics_comparison.dart';
import '../../../../core/theme/app_colors.dart';
import '../../core/models/report_metric_model.dart';
import 'analytics_formatters.dart';
import 'analytics_kpi_builder.dart';

class ComparisonMetricCard extends StatelessWidget {
  const ComparisonMetricCard({
    super.key,
    required this.title,
    required this.delta,
    this.formatValue,
    this.invertGrowth = false,
  });

  final String title;
  final ComparisonDelta delta;
  final String Function(double value)? formatValue;
  final bool invertGrowth;

  @override
  Widget build(BuildContext context) {
    final semantic = invertGrowth
        ? AnalyticsKpi.growthSemantic(delta.percent, invert: true)
        : delta.semantic;
    final trendColor = _colorFor(semantic);
    final trendIcon = _iconFor(delta.percent, invert: invertGrowth);
    final valueText = formatValue?.call(delta.current) ?? AnalyticsFormatters.money(delta.current);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              valueText,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'السابق: ${formatValue?.call(delta.previous) ?? AnalyticsFormatters.money(delta.previous)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Badge(label: delta.absoluteLabel, color: trendColor, icon: trendIcon),
                _Badge(label: delta.percentLabel, color: trendColor, icon: trendIcon),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFor(ReportTrendSemantic semantic) => switch (semantic) {
        ReportTrendSemantic.positive => AppColors.success,
        ReportTrendSemantic.negative => AppColors.error,
        ReportTrendSemantic.warning => AppColors.warning,
        ReportTrendSemantic.neutral => AppColors.textSecondary,
      };

  IconData _iconFor(double percent, {required bool invert}) {
    if (percent.abs() < 0.5) return Icons.remove_rounded;
    final up = percent > 0;
    final good = invert ? !up : up;
    return good ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
