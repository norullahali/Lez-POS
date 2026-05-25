import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/permissions/permission_keys.dart';
import '../../auth/providers/permission_provider.dart';
import '../../inventory/providers/inventory_provider.dart';
import '../jobs/background_job_registry.dart';
import '../models/background_job_execution_result.dart';
import '../models/cashier_behavior_models.dart';
import '../models/daily_closing_summary.dart';
import '../models/daily_operational_snapshot.dart';
import '../models/expiry_alert.dart';
import '../models/low_stock_prediction.dart';
import '../models/operational_alert.dart';
import '../models/operational_insight.dart';
import '../models/scheduled_report_config.dart';
import '../models/store_operational_health.dart';
import '../repositories/operations_intelligence_repository.dart';
import '../services/cashier_behavior_monitor.dart';
import '../services/daily_closing_service.dart';
import '../services/daily_snapshot_service.dart';
import '../services/expiry_monitoring_service.dart';
import '../services/insights_feed_service.dart';
import '../services/inventory_warning_engine.dart';
import '../services/low_stock_prediction_service.dart';
import '../services/operational_alert_service.dart';
import '../services/operational_health_service.dart';
import '../services/scheduled_reports_service.dart';
import '../services/suspicious_activity_detector.dart';

final operationsRepositoryProvider = Provider<OperationsIntelligenceRepository>((ref) {
  return OperationsIntelligenceRepository(AppDatabase.instance);
});

final inventoryWarningEngineProvider = Provider<InventoryWarningEngine>((ref) {
  return InventoryWarningEngine(
    ref.watch(operationsRepositoryProvider),
    ref.watch(inventoryRepositoryProvider),
  );
});

final expiryMonitoringServiceProvider = Provider<ExpiryMonitoringService>((ref) {
  return ExpiryMonitoringService(
    ref.watch(operationsRepositoryProvider),
    ref.watch(inventoryRepositoryProvider),
  );
});

final lowStockPredictionServiceProvider = Provider<LowStockPredictionService>((ref) {
  return LowStockPredictionService(ref.watch(operationsRepositoryProvider));
});

final suspiciousActivityDetectorProvider = Provider<SuspiciousActivityDetector>((ref) {
  return SuspiciousActivityDetector(ref.watch(operationsRepositoryProvider));
});

final cashierBehaviorMonitorProvider = Provider<CashierBehaviorMonitor>((ref) {
  return CashierBehaviorMonitor(ref.watch(operationsRepositoryProvider));
});

final dailyClosingServiceProvider = Provider<DailyClosingService>((ref) {
  return DailyClosingService(
    ref.watch(operationsRepositoryProvider),
    ref.watch(inventoryWarningEngineProvider),
  );
});

final operationalHealthServiceProvider = Provider<OperationalHealthService>((ref) {
  return OperationalHealthService(ref.watch(operationsRepositoryProvider));
});

final dailySnapshotServiceProvider = Provider<DailySnapshotService>((ref) {
  return DailySnapshotService(
    ref.watch(dailyClosingServiceProvider),
    ref.watch(operationalHealthServiceProvider),
  );
});

final operationalAlertServiceProvider = Provider<OperationalAlertService>((ref) {
  return OperationalAlertService(
    repo: ref.watch(operationsRepositoryProvider),
    inventoryEngine: ref.watch(inventoryWarningEngineProvider),
    expiryService: ref.watch(expiryMonitoringServiceProvider),
    predictionService: ref.watch(lowStockPredictionServiceProvider),
    suspiciousDetector: ref.watch(suspiciousActivityDetectorProvider),
    cashierMonitor: ref.watch(cashierBehaviorMonitorProvider),
    snapshotService: ref.watch(dailySnapshotServiceProvider),
  );
});

final insightsFeedServiceProvider = Provider<InsightsFeedService>((ref) {
  return InsightsFeedService(
    repo: ref.watch(operationsRepositoryProvider),
    alertService: ref.watch(operationalAlertServiceProvider),
    closingService: ref.watch(dailyClosingServiceProvider),
    predictionService: ref.watch(lowStockPredictionServiceProvider),
    cashierMonitor: ref.watch(cashierBehaviorMonitorProvider),
  );
});

final scheduledReportsServiceProvider = Provider<ScheduledReportsService>((ref) {
  return ScheduledReportsService(
    ref.watch(dailyClosingServiceProvider),
    ref.watch(lowStockPredictionServiceProvider),
  );
});

final backgroundJobRegistryProvider = Provider<BackgroundJobRegistry>((ref) {
  return BackgroundJobRegistry(
    alertService: ref.watch(operationalAlertServiceProvider),
    scheduledReports: ref.watch(scheduledReportsServiceProvider),
    snapshotService: ref.watch(dailySnapshotServiceProvider),
  );
});

final backgroundJobRunnerProvider = Provider<BackgroundJobRunner>((ref) {
  return BackgroundJobRunner(ref.watch(backgroundJobRegistryProvider).buildJobs());
});

final backgroundJobResultsProvider = Provider<Map<String, BackgroundJobExecutionResult>>((ref) {
  ref.watch(operationsStartupProvider);
  return ref.read(backgroundJobRunnerProvider).lastResults;
});

final canViewOperationsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.operationsView));
});

final canViewAlertsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.alertsView)) ||
      ref.watch(permissionProvider(PermissionKeys.operationsView));
});

final operationalAlertsProvider =
    AsyncNotifierProvider<OperationalAlertsNotifier, List<OperationalAlert>>(
  OperationalAlertsNotifier.new,
);

class OperationalAlertsNotifier extends AsyncNotifier<List<OperationalAlert>> {
  @override
  Future<List<OperationalAlert>> build() async {
    if (!ref.watch(canViewAlertsProvider)) return [];
    return ref.watch(operationalAlertServiceProvider).loadAlerts();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    await ref.read(operationalAlertServiceProvider).refresh();
    state = AsyncData(await ref.read(operationalAlertServiceProvider).loadAlerts());
  }

  Future<void> dismiss(String fingerprint) async {
    await ref.read(operationalAlertServiceProvider).dismissAlert(fingerprint);
    ref.invalidateSelf();
  }

  Future<void> acknowledge(String fingerprint) async {
    await ref.read(operationalAlertServiceProvider).acknowledgeAlert(fingerprint);
    ref.invalidateSelf();
  }

  Future<void> resolve(String fingerprint) async {
    await ref.read(operationalAlertServiceProvider).resolveAlert(fingerprint);
    ref.invalidateSelf();
  }
}

final operationalUnreadCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(operationalAlertsProvider).valueOrNull ?? [];
  return alerts.where((a) => a.isUnread).length;
});

final operationalInsightsProvider =
    FutureProvider<List<OperationalInsight>>((ref) async {
  if (!ref.watch(canViewOperationsProvider)) return [];
  return ref.watch(insightsFeedServiceProvider).buildFeed();
});

final storeOperationalHealthProvider =
    FutureProvider<StoreOperationalHealth>((ref) async {
  if (!ref.watch(canViewOperationsProvider)) {
    return StoreOperationalHealth(
      score: 100,
      status: StoreHealthStatus.excellent,
      factors: const [],
      evaluatedAt: DateTime.now(),
    );
  }
  final alerts = ref.watch(operationalAlertsProvider).valueOrNull;
  return ref.watch(operationalHealthServiceProvider).evaluate(alerts: alerts);
});

final dailyOperationalSnapshotsProvider =
    FutureProvider<List<DailyOperationalSnapshot>>((ref) async {
  return ref.watch(dailySnapshotServiceProvider).loadSnapshots();
});

final dailyClosingSummaryProvider =
    FutureProvider<DailyClosingSummary>((ref) async {
  if (!ref.watch(canViewOperationsProvider)) {
    return DailyClosingSummary(
      date: DateTime.now(),
      totalSales: 0,
      invoiceCount: 0,
      totalReturns: 0,
      returnRatePercent: 0,
      inventoryAlerts: 0,
      debtReceivable: 0,
      debtPayable: 0,
      topProductName: null,
      weakCategoryName: null,
      topCashierName: null,
      sessionMismatchCount: 0,
      insightLines: const [],
    );
  }
  return ref.watch(dailyClosingServiceProvider).buildSummary();
});

final expiryMonitoringProvider =
    FutureProvider<ExpiryMonitoringSnapshot>((ref) async {
  return ref.watch(expiryMonitoringServiceProvider).snapshot();
});

final lowStockPredictionsProvider =
    FutureProvider<List<LowStockPrediction>>((ref) async {
  return ref.watch(lowStockPredictionServiceProvider).predict();
});

final cashierBehaviorProvider =
    FutureProvider<List<CashierBehaviorRow>>((ref) async {
  if (!ref.watch(canViewOperationsProvider)) return [];
  return ref.watch(cashierBehaviorMonitorProvider).evaluateRows();
});

final scheduledReportsConfigProvider =
    FutureProvider<List<ScheduledReportConfig>>((ref) async {
  return ref.watch(scheduledReportsServiceProvider).loadConfigs();
});

final operationsStartupProvider = Provider<void>((ref) {
  ref.listen(backgroundJobRunnerProvider, (_, __) {});
  Future.microtask(() {
    ref.read(backgroundJobRunnerProvider).initializeOnStartup();
  });
});