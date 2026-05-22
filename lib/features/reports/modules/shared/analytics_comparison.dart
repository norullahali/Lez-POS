import 'analytics_formatters.dart';
import 'analytics_kpi_builder.dart';
import '../../core/models/report_metric_model.dart';

class ComparisonDelta {
  const ComparisonDelta({
    required this.current,
    required this.previous,
    required this.absolute,
    required this.percent,
    required this.semantic,
  });

  final double current;
  final double previous;
  final double absolute;
  final double percent;
  final ReportTrendSemantic semantic;

  static ComparisonDelta compute(
    double previous,
    double current, {
    bool invertGrowth = false,
  }) {
    final absolute = current - previous;
    final percent = previous == 0 ? (current > 0 ? 100.0 : 0.0) : (absolute / previous.abs()) * 100;
    return ComparisonDelta(
      current: current,
      previous: previous,
      absolute: absolute,
      percent: percent,
      semantic: AnalyticsKpi.growthSemantic(percent, invert: invertGrowth),
    );
  }

  String get absoluteLabel => AnalyticsFormatters.signedMoney(absolute);
  String get percentLabel => AnalyticsFormatters.signedPercent(percent);
}
