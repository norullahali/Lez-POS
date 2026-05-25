import '../config/operations_thresholds.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_insight.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'cashier_behavior_monitor.dart';
import 'daily_closing_service.dart';
import 'low_stock_prediction_service.dart';
import 'operational_alert_service.dart';
import 'operational_evaluation_cache.dart';

class InsightsFeedService {
  InsightsFeedService({
    required OperationsIntelligenceRepository repo,
    required OperationalAlertService alertService,
    required DailyClosingService closingService,
    required LowStockPredictionService predictionService,
    required CashierBehaviorMonitor cashierMonitor,
  })  : _repo = repo,
        _alertService = alertService,
        _closingService = closingService,
        _predictionService = predictionService,
        _cashierMonitor = cashierMonitor;

  final OperationsIntelligenceRepository _repo;
  final OperationalAlertService _alertService;
  final DailyClosingService _closingService;
  final LowStockPredictionService _predictionService;
  final CashierBehaviorMonitor _cashierMonitor;

  Future<List<OperationalInsight>> buildFeed() async {
    final now = DateTime.now();
    final insights = <OperationalInsight>[];

    final returnRate = await OperationalEvaluationCache.memo(
      'return_rate',
      () => _repo.fetchReturnRateComparison(),
    );
    final todayReturns = (returnRate['today_returns'] as num?)?.toDouble() ?? 0;
    final avgDaily = (returnRate['avg_daily_returns'] as num?)?.toDouble() ?? 0;
    if (avgDaily > 0 && todayReturns > avgDaily) {
      final pct = ((todayReturns - avgDaily) / avgDaily * 100).clamp(0, 999);
      insights.add(OperationalInsight(
        id: 'insight_returns_up',
        message: 'المرتجعات اليوم أعلى من المتوسط بنسبة ${pct.toStringAsFixed(0)}%',
        severity: OperationalAlertSeverity.warning,
        createdAt: now,
        category: 'returns',
        actionRoute: '/return-analytics',
        priorityScore: 72,
        urgencyScore: 22,
      ));
    }

    final dead = await OperationalEvaluationCache.memo(
      'dead_stock_insight',
      () => _repo.fetchDeadStockProducts(
        days: OperationsThresholds.deadStockInsightDays,
      ),
    );
    if (dead.isNotEmpty) {
      final name = dead.first['name'] as String? ?? 'منتج';
      insights.add(OperationalInsight(
        id: 'insight_dead_${dead.first['id']}',
        message:
            '$name لم يتحرك منذ ${OperationsThresholds.deadStockInsightDays} يوماً',
        severity: OperationalAlertSeverity.info,
        createdAt: now,
        category: 'inventory',
        actionRoute: '/inventory',
        priorityScore: 45,
        urgencyScore: 12,
      ));
    }

    final cashiers = await _cashierMonitor.evaluateRows();
    if (cashiers.isNotEmpty) {
      final top = cashiers.first;
      insights.add(OperationalInsight(
        id: 'insight_cashier_${top.userId}',
        message: 'مرتجعات ${top.name} تتجاوز المتوسط (${top.refundCount} اليوم)',
        severity: OperationalAlertSeverity.warning,
        createdAt: now,
        category: 'cashier',
        actionRoute: '/activity/timeline',
        priorityScore: 58,
        urgencyScore: 18,
      ));
    }

    final invChange = await OperationalEvaluationCache.memo(
      'inv_value_change',
      () => _repo.fetchInventoryValueChangeWeek(),
    );
    if (invChange < 0) {
      insights.add(OperationalInsight(
        id: 'insight_inv_drop',
        message: 'قيمة المخزون انخفضت هذا الأسبوع',
        severity: OperationalAlertSeverity.info,
        createdAt: now,
        category: 'inventory',
        actionRoute: '/reports',
        priorityScore: 40,
        urgencyScore: 10,
      ));
    }

    final closing = await _closingService.buildSummary();
    if (closing.weakCategoryName != null) {
      insights.add(OperationalInsight(
        id: 'insight_weak_cat',
        message: 'فئة ${closing.weakCategoryName} الأضعف مبيعاً اليوم',
        severity: OperationalAlertSeverity.info,
        createdAt: now,
        category: 'sales',
        actionRoute: '/reports',
        priorityScore: 35,
        urgencyScore: 8,
      ));
    }

    final predictions = await _predictionService.predict();
    for (final p in predictions
        .where((p) => p.urgency.name != 'safe')
        .take(3)) {
      insights.add(OperationalInsight(
        id: 'insight_predict_${p.productId}',
        message:
            '${p.productName}: ~${p.daysRemaining.toStringAsFixed(0)} يوم متبقي',
        severity: p.urgency.name == 'critical'
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        createdAt: now,
        category: 'inventory',
        actionRoute: '/inventory',
        priorityScore: p.urgency.name == 'critical' ? 80 : 60,
        urgencyScore: p.urgency.name == 'critical' ? 30 : 20,
      ));
    }

    final alerts = await _alertService.loadAlerts(useCache: true);
    final unread = alerts.where((a) => a.isUnread).length;
    if (unread > 0) {
      insights.add(OperationalInsight(
        id: 'insight_alert_count',
        message: '$unread تنبيه تشغيلي يحتاج مراجعة',
        severity: OperationalAlertSeverity.warning,
        createdAt: now,
        category: 'alerts',
        actionRoute: '/operations/notifications',
        priorityScore: 90,
        urgencyScore: 35,
      ));
    }

    insights.sort(OperationalInsight.compare);
    return insights;
  }
}