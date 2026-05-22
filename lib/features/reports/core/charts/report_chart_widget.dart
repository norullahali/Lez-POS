import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/report_chart_models.dart';
import '../widgets/report_empty_view.dart';
import '../widgets/report_loading_view.dart';

class ReportChartWidget extends StatelessWidget {
  const ReportChartWidget({
    super.key,
    required this.config,
    this.isLoading = false,
    this.height = 280,
    this.expand = false,
  });

  final ReportChartConfig config;
  final bool isLoading;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: expand ? null : height,
        child: expand
            ? const Center(child: ReportLoadingView())
            : const ReportLoadingView(),
      );
    }

    if (config.series.isEmpty || config.series.first.points.isEmpty) {
      return SizedBox(
        height: expand ? null : height,
        child: ReportEmptyView(icon: Icons.bar_chart_rounded, message: config.emptyMessage),
      );
    }

    final chart = RepaintBoundary(child: _ChartBody(config: config));

    if (expand) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(height: constraints.maxHeight, child: chart);
        },
      );
    }

    return SizedBox(height: height, child: chart);
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({required this.config});
  final ReportChartConfig config;

  @override
  Widget build(BuildContext context) {
    return switch (config.type) {
      ReportChartType.line || ReportChartType.trend => _LineChartBody(config: config),
      ReportChartType.bar => _BarChartBody(config: config),
      ReportChartType.pie => _PieChartBody(config: config),
    };
  }
}

class _LineChartBody extends StatelessWidget {
  const _LineChartBody({required this.config});
  final ReportChartConfig config;

  @override
  Widget build(BuildContext context) {
    final series = config.series.first;
    final spots = series.points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.value)).toList();
    final maxY = series.points.fold<double>(0, (m, p) => p.value > m ? p.value : m);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        titlesData: _axisTitles(
          series.points.map((p) => p.label).toList(),
          zeroBased: true,
          yFormatter: config.yAxisFormatter,
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.x.toInt();
              final label = i >= 0 && i < series.points.length ? series.points[i].label : '';
              return LineTooltipItem(
                '${series.label}\n$label\n${_formatY(s.y)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: config.type == ReportChartType.trend,
            color: series.color,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: config.type == ReportChartType.trend,
              color: series.color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatY(double value) => config.yAxisFormatter?.call(value) ?? value.toStringAsFixed(0);
}

class _BarChartBody extends StatelessWidget {
  const _BarChartBody({required this.config});
  final ReportChartConfig config;

  @override
  Widget build(BuildContext context) {
    final primary = config.series.first;
    final secondary = config.secondarySeries;
    final maxY = [
      ...primary.points.map((p) => p.value),
      if (secondary != null) ...secondary.points.map((p) => p.value),
    ].fold<double>(0, (m, v) => v > m ? v : m);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.2,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final i = group.x - 1;
              final label = i >= 0 && i < primary.points.length ? primary.points[i].label : '';
              final seriesLabel = rodIndex == 0
                  ? primary.label
                  : (secondary?.label ?? primary.label);
              return BarTooltipItem(
                '$seriesLabel\n$label\n${_formatY(rod.toY)}',
                const TextStyle(color: Colors.white, fontSize: 11),
              );
            },
          ),
        ),
        titlesData: _axisTitles(
          primary.points.map((p) => p.label).toList(),
          yFormatter: config.yAxisFormatter,
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: primary.points.asMap().entries.map((e) {
          final rods = <BarChartRodData>[
            BarChartRodData(
              toY: e.value.value,
              color: primary.color,
              width: secondary == null ? 18 : 14,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ];
          if (secondary != null && e.key < secondary.points.length) {
            rods.add(
              BarChartRodData(
                toY: secondary.points[e.key].value,
                color: secondary.color,
                width: 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            );
          }
          return BarChartGroupData(x: e.key + 1, barRods: rods);
        }).toList(),
      ),
    );
  }

  String _formatY(double value) => config.yAxisFormatter?.call(value) ?? value.toStringAsFixed(0);
}

class _PieChartBody extends StatelessWidget {
  const _PieChartBody({required this.config});
  final ReportChartConfig config;

  @override
  Widget build(BuildContext context) {
    final points = config.series.first.points;
    final total = points.fold<double>(0, (s, p) => s + p.value);
    if (total <= 0) {
      return ReportEmptyView(icon: Icons.pie_chart_outline_rounded, message: config.emptyMessage);
    }

    final colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.success,
      AppColors.warning,
      AppColors.info,
      AppColors.error,
    ];

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 36,
        sections: points.asMap().entries.map((e) {
          final pct = (e.value.value / total) * 100;
          return PieChartSectionData(
            value: e.value.value,
            title: '${pct.toStringAsFixed(0)}%',
            radius: 56,
            color: colors[e.key % colors.length],
            titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          );
        }).toList(),
      ),
    );
  }
}

FlTitlesData _axisTitles(
  List<String> labels, {
  bool zeroBased = false,
  String Function(double value)? yFormatter,
}) {
  return FlTitlesData(
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        getTitlesWidget: (v, _) {
          final i = zeroBased ? v.toInt() : v.toInt() - 1;
          if (i < 0 || i >= labels.length) return const SizedBox.shrink();
          final label = labels[i];
          final short = label.length > 8 ? '${label.substring(0, 8)}…' : label;
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(short, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
          );
        },
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 52,
        getTitlesWidget: (v, meta) {
          if (meta.max == v) return const SizedBox.shrink();
          final text = yFormatter?.call(v) ??
              (v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toInt().toString());
          return Text(text, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary));
        },
      ),
    ),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}
