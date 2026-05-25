import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scheduled_report_config.dart';
import 'daily_closing_service.dart';
import 'low_stock_prediction_service.dart';

class ScheduledReportsService {
  ScheduledReportsService(this._closing, this._predictions);

  final DailyClosingService _closing;
  final LowStockPredictionService _predictions;

  static const _prefsKey = 'operations_scheduled_reports';

  static const defaultConfigs = [
    ScheduledReportConfig(
      id: 'daily_ops',
      titleAr: 'تقرير التشغيل اليومي',
      frequency: ScheduledReportFrequency.daily,
      enabled: true,
    ),
    ScheduledReportConfig(
      id: 'weekly_inventory',
      titleAr: 'تقرير المخزون الأسبوعي',
      frequency: ScheduledReportFrequency.weekly,
      enabled: true,
    ),
    ScheduledReportConfig(
      id: 'monthly_summary',
      titleAr: 'ملخص شهري',
      frequency: ScheduledReportFrequency.monthly,
      enabled: false,
    ),
  ];

  Future<List<ScheduledReportConfig>> loadConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return List.from(defaultConfigs);
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _configFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return List.from(defaultConfigs);
    }
  }

  Future<void> saveConfigs(List<ScheduledReportConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(configs.map(_configToJson).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  Future<ScheduledReportConfig?> generateIfDue(ScheduledReportConfig config) async {
    if (!config.enabled) return null;
    if (!_isDue(config)) return null;
    return generateNow(config);
  }

  bool _isDue(ScheduledReportConfig config) {
    final last = config.lastGeneratedAt;
    if (last == null) return true;
    final now = DateTime.now();
    switch (config.frequency) {
      case ScheduledReportFrequency.daily:
        return now.difference(last).inHours >= 20;
      case ScheduledReportFrequency.weekly:
        return now.difference(last).inDays >= 6;
      case ScheduledReportFrequency.monthly:
        return now.month != last.month || now.year != last.year;
    }
  }

  Future<ScheduledReportConfig> generateNow(ScheduledReportConfig config) async {
    final dir = await _reportsDir();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final file = File('${dir.path}/${config.id}_$stamp.csv');

    final buffer = StringBuffer('\uFEFF');
    buffer.writeln('# ${config.titleAr}');
    buffer.writeln('# Generated: ${DateTime.now()}');

    switch (config.id) {
      case 'daily_ops':
        await _writeDailyOps(buffer);
      case 'weekly_inventory':
        await _writeInventory(buffer);
      default:
        await _writeDailyOps(buffer);
    }

    await file.writeAsString(buffer.toString(), encoding: utf8);
    return config.copyWith(
      lastGeneratedAt: DateTime.now(),
      lastFilePath: file.path,
    );
  }

  Future<void> _writeDailyOps(StringBuffer buffer) async {
    final summary = await _closing.buildSummary();
    buffer.writeln('metric,value');
    buffer.writeln('total_sales,${summary.totalSales}');
    buffer.writeln('invoice_count,${summary.invoiceCount}');
    buffer.writeln('total_returns,${summary.totalReturns}');
    buffer.writeln('return_rate,${summary.returnRatePercent}');
    buffer.writeln('receivable,${summary.debtReceivable}');
    buffer.writeln('payable,${summary.debtPayable}');
    buffer.writeln('session_mismatches,${summary.sessionMismatchCount}');
  }

  Future<void> _writeInventory(StringBuffer buffer) async {
    final preds = await _predictions.predict();
    buffer.writeln('product,stock,daily_rate,days_remaining,urgency');
    for (final p in preds.take(50)) {
      buffer.writeln(
        '${_csv(p.productName)},${p.currentStock},${p.dailySalesRate},${p.daysRemaining},${p.urgency.name}',
      );
    }
  }

  Future<Directory> _reportsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/LezPOS/scheduled_reports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _csv(String value) {
    if (value.contains(',') || value.contains('"')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static Map<String, dynamic> _configToJson(ScheduledReportConfig c) => {
        'id': c.id,
        'titleAr': c.titleAr,
        'frequency': c.frequency.name,
        'enabled': c.enabled,
        'lastGeneratedAt': c.lastGeneratedAt?.toIso8601String(),
        'lastFilePath': c.lastFilePath,
      };

  static ScheduledReportConfig _configFromJson(Map<String, dynamic> json) {
    return ScheduledReportConfig(
      id: json['id'] as String,
      titleAr: json['titleAr'] as String,
      frequency: ScheduledReportFrequency.values.firstWhere(
        (e) => e.name == json['frequency'],
        orElse: () => ScheduledReportFrequency.daily,
      ),
      enabled: json['enabled'] as bool? ?? true,
      lastGeneratedAt: json['lastGeneratedAt'] != null
          ? DateTime.tryParse(json['lastGeneratedAt'] as String)
          : null,
      lastFilePath: json['lastFilePath'] as String?,
    );
  }
}
