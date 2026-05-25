import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/operations_thresholds.dart';
import '../models/daily_operational_snapshot.dart';
import '../models/operational_alert.dart';
import 'daily_closing_service.dart';
import 'operational_health_service.dart';

class DailySnapshotService {
  DailySnapshotService(this._closing, this._health);

  final DailyClosingService _closing;
  final OperationalHealthService _health;

  static const _key = 'operations_daily_snapshots';

  Future<void> captureTodayIfNeeded({List<OperationalAlert>? alerts}) async {
    final todayKey = _dateKey(DateTime.now());
    final existing = await loadSnapshots();
    if (existing.any((s) => s.dateKey == todayKey)) return;

    final summary = await _closing.buildSummary();
    final health = await _health.evaluate(alerts: alerts);
    final snapshot = DailyOperationalSnapshot(
      dateKey: todayKey,
      totalSales: summary.totalSales,
      invoiceCount: summary.invoiceCount,
      totalReturns: summary.totalReturns,
      returnRatePercent: summary.returnRatePercent,
      inventoryAlertsCount: summary.inventoryAlerts,
      debtReceivable: summary.debtReceivable,
      debtPayable: summary.debtPayable,
      sessionMismatchCount: summary.sessionMismatchCount,
      suspiciousSignalsCount: alerts
              ?.where((a) => a.type.name.contains('suspicious') || a.type.name.contains('unusual'))
              .length ??
          0,
      healthScore: health.score,
      capturedAt: DateTime.now(),
    );

    final updated = [snapshot, ...existing]
        .take(OperationsThresholds.maxStoredSnapshots)
        .toList();
    await _save(updated);
  }

  Future<List<DailyOperationalSnapshot>> loadSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => DailyOperationalSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<DailyOperationalSnapshot> snapshots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(snapshots.map((s) => s.toJson()).toList()),
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}