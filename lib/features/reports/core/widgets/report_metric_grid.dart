import 'package:flutter/material.dart';
import '../models/report_metric_model.dart';
import 'report_metric_card.dart';

class ReportMetricGrid extends StatelessWidget {
  const ReportMetricGrid({
    super.key,
    required this.metrics,
    this.crossAxisCount = 3,
    this.childAspectRatio = 2.2,
    this.spacing = 16,
  });

  final List<ReportMetricModel> metrics;
  final int crossAxisCount;
  final double childAspectRatio;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
      childAspectRatio: childAspectRatio,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: metrics.map((m) => ReportMetricCard(metric: m)).toList(),
    );
  }
}