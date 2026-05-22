import '../../core/models/report_filter_model.dart';
import 'analytics_formatters.dart';

/// Normalized CSV export rows and metadata for advanced analytics.
class AnalyticsExportFormatter {
  AnalyticsExportFormatter._();

  static List<List<String>> metricSection(Map<String, num> metrics) {
    return metrics.entries.map((e) => [e.key, _cell(e.value)]).toList();
  }

  static List<List<String>> tableRows(List<List<Object?>> rows) {
    return rows.map((r) => r.map(_cell).toList()).toList();
  }

  static String filterSummary(ReportFilterModel filter) => filter.summaryAr();

  static String generatedAtLabel([DateTime? at]) => AnalyticsFormatters.exportTime(at);

  static String _cell(Object? value) {
    if (value == null) return AnalyticsFormatters.empty;
    if (value is double) return AnalyticsFormatters.currency.format(value);
    if (value is int) return AnalyticsFormatters.currency.format(value);
    return value.toString();
  }
}
