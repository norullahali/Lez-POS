import '../cache/operations_cache.dart';
import '../config/operations_thresholds.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'alert_builder.dart';
import 'alert_deduplication_service.dart';
import 'alert_fatigue_guard.dart';
import 'alert_lifecycle_store.dart';
import 'alert_priority_scorer.dart';
import 'cashier_behavior_monitor.dart';
import 'daily_snapshot_service.dart';
import 'expiry_monitoring_service.dart';
import 'inventory_warning_engine.dart';
import 'low_stock_prediction_service.dart';
import 'operational_evaluation_cache.dart';
import 'suspicious_activity_detector.dart';

class OperationalAlertService {
  OperationalAlertService({
    required OperationsIntelligenceRepository repo,
    required InventoryWarningEngine inventoryEngine,
    required ExpiryMonitoringService expiryService,
    required LowStockPredictionService predictionService,
    required SuspiciousActivityDetector suspiciousDetector,
    required CashierBehaviorMonitor cashierMonitor,
    DailySnapshotService? snapshotService,
  })  : _repo = repo,
        _inventoryEngine = inventoryEngine,
        _expiryService = expiryService,
        _predictionService = predictionService,
        _suspiciousDetector = suspiciousDetector,
        _cashierMonitor = cashierMonitor,
        _snapshotService = snapshotService;

  final OperationsIntelligenceRepository _repo;
  final InventoryWarningEngine _inventoryEngine;
  final ExpiryMonitoringService _expiryService;
  final LowStockPredictionService _predictionService;
  final SuspiciousActivityDetector _suspiciousDetector;
  final CashierBehaviorMonitor _cashierMonitor;
  final DailySnapshotService? _snapshotService;

  static const _cacheKey = 'ops_alerts_bundle_v2';

  Future<List<OperationalAlert>> loadAlerts({bool useCache = true}) async {
    if (useCache) {
      final cached = OperationsCache.get<List<OperationalAlert>>(_cacheKey);
      if (cached != null) return cached;
    }

    OperationalEvaluationCache.clear();

    final results = await Future.wait([
      _inventoryEngine.evaluate(),
      _expiryService.evaluateAlerts(),
      _predictionService.evaluateAlerts(),
      _suspiciousDetector.evaluate(),
      _cashierMonitor.evaluateAlerts(),
      _evaluateFinancialAndSessionAlerts(),
    ]);

    final merged = <OperationalAlert>[];
    for (final batch in results) {
      merged.addAll(batch);
    }

    final deduped = await AlertDeduplicationService.process(merged);
    final grouped = AlertFatigueGuard.apply(deduped);
    grouped.sort(AlertPriorityScorer.compare);

    OperationsCache.set(_cacheKey, grouped);
    await _snapshotService?.captureTodayIfNeeded(alerts: grouped);
    return grouped;
  }

  Future<void> refresh() async {
    OperationsCache.invalidatePrefix('ops_');
    OperationalEvaluationCache.clear();
    await loadAlerts(useCache: false);
  }

  Future<void> dismissAlert(String alertIdOrFingerprint) async {
    await AlertLifecycleStore.dismiss(alertIdOrFingerprint);
    OperationsCache.invalidatePrefix('ops_');
  }

  Future<void> acknowledgeAlert(String fingerprint) async {
    await AlertLifecycleStore.acknowledge(fingerprint);
    OperationsCache.invalidatePrefix('ops_');
  }

  Future<void> resolveAlert(String fingerprint) async {
    await AlertLifecycleStore.resolve(fingerprint);
    OperationsCache.invalidatePrefix('ops_');
  }

  Future<List<OperationalAlert>> _evaluateFinancialAndSessionAlerts() async {
    final alerts = <OperationalAlert>[];
    final now = DateTime.now();

    final sales = await OperationalEvaluationCache.memo(
      'sales_comparison_today',
      () => _repo.fetchSalesComparisonToday(),
    );
    final todaySales = (sales['today_sales'] as num?)?.toDouble() ?? 0;
    final yesterdaySales = (sales['yesterday_sales'] as num?)?.toDouble() ?? 0;
    if (yesterdaySales > OperationsThresholds.weakSalesMinYesterday &&
        todaySales < yesterdaySales * OperationsThresholds.weakSalesRatio) {
      final drop = yesterdaySales > 0
          ? ((yesterdaySales - todaySales) / yesterdaySales * 100)
          : 0.0;
      alerts.add(OperationalAlertBuilder.create(
        id: 'weak_sales_today',
        type: OperationalAlertType.weakSales,
        severity: drop >= OperationsThresholds.weakSalesCriticalDropPercent
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'مبيعات أضعف من أمس',
        description:
            'اليوم ${todaySales.toStringAsFixed(0)} مقابل ${yesterdaySales.toStringAsFixed(0)} أمس',
        reason:
            'مبيعات اليوم (${todaySales.toStringAsFixed(0)}) أقل من ${(OperationsThresholds.weakSalesRatio * 100).toInt()}% من أمس (انخفاض ~${drop.toStringAsFixed(0)}%)',
        createdAt: now,
        actionRoute: '/reports',
      ));
    }

    final debts = await OperationalEvaluationCache.memo(
      'overdue_debts',
      () => _repo.fetchOverdueDebts(minBalance: OperationsThresholds.overdueDebtMinBalance),
    );
    for (final row in debts.take(5)) {
      final id = row['id'] as int;
      final balance = (row['balance'] as num).toDouble();
      alerts.add(OperationalAlertBuilder.create(
        id: 'debt_$id',
        type: OperationalAlertType.overdueDebt,
        severity: balance >= OperationsThresholds.overdueDebtCriticalBalance
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'ذمة مستحقة: ${row['name']}',
        description: 'الرصيد ${balance.toStringAsFixed(0)}',
        reason:
            'رصيد العميل (${balance.toStringAsFixed(0)}) ≥ الحد (${OperationsThresholds.overdueDebtMinBalance.toInt()})',
        createdAt: now,
        entityType: 'customer',
        entityId: id,
        actionRoute: '/customers/profile/$id',
      ));
    }

    final sessions = await OperationalEvaluationCache.memo(
      'session_mismatches',
      () => _repo.fetchSessionMismatches(minDiff: OperationsThresholds.sessionMismatchMinDiff),
    );
    for (final row in sessions.take(5)) {
      final sessionId = row['id'] as int;
      final diff = (row['cash_difference'] as num).toDouble();
      alerts.add(OperationalAlertBuilder.create(
        id: 'session_mismatch_$sessionId',
        type: OperationalAlertType.sessionMismatch,
        severity: diff.abs() >= OperationsThresholds.sessionMismatchCriticalDiff
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'فرق جلسة: ${row['cashier_name']}',
        description: 'فرق نقدي ${diff.toStringAsFixed(0)}',
        reason:
            'فرق النقد عند إغلاق الجلسة (${diff.toStringAsFixed(0)}) ≥ ${OperationsThresholds.sessionMismatchMinDiff.toInt()}',
        createdAt: now,
        entityType: 'session',
        entityId: sessionId,
        actionRoute: '/activity',
      ));
    }

    return alerts;
  }
}