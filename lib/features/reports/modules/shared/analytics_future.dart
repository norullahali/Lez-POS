import '../../core/models/report_tab_id.dart';
import 'advanced_analytics_models.dart';

abstract class AnalyticsForecastService {
  Future<List<AnalyticsTrendPoint>> forecastRevenue({
    required DateTime from,
    required DateTime to,
    required int horizonDays,
  });
}

abstract class AnalyticsInsightService {
  Future<List<String>> generateInsights({required ReportTabId tabId});
}

abstract class AnalyticsAnomalyDetector {
  Future<List<String>> detectAnomalies({
    required ReportTabId tabId,
    required AnalyticsDateRange range,
  });
}