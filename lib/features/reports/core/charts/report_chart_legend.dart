import 'package:flutter/material.dart';
import '../models/report_chart_models.dart';

class ReportChartLegend extends StatelessWidget {
  const ReportChartLegend({super.key, required this.config});

  final ReportChartConfig config;

  @override
  Widget build(BuildContext context) {
    final items = <ReportChartSeries>[
      ...config.series,
      if (config.secondarySeries != null) config.secondarySeries!,
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 8,
        children: items.map((s) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(s.label, style: const TextStyle(fontSize: 12)),
            ],
          );
        }).toList(),
      ),
    );
  }
}