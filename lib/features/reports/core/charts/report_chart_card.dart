import 'package:flutter/material.dart';
import '../models/report_chart_models.dart';
import 'report_chart_legend.dart';
import 'report_chart_widget.dart';

class ReportChartCard extends StatelessWidget {
  const ReportChartCard({
    super.key,
    required this.config,
    this.isLoading = false,
    this.showLegend = true,
  });

  final ReportChartConfig config;
  final bool isLoading;
  final bool showLegend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(config.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            Expanded(
              child: RepaintBoundary(
                child: ReportChartWidget(
                  config: config,
                  isLoading: isLoading,
                  expand: true,
                ),
              ),
            ),
            if (showLegend) ReportChartLegend(config: config),
          ],
        ),
      ),
    );
  }
}