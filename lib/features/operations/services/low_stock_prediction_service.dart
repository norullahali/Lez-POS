import '../config/operations_thresholds.dart';
import '../models/low_stock_prediction.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'alert_builder.dart';

class LowStockPredictionService {
  LowStockPredictionService(this._repo);

  final OperationsIntelligenceRepository _repo;

  Future<List<LowStockPrediction>> predict({int? velocityDays}) async {
    final days = velocityDays ?? OperationsThresholds.velocityDays;
    final rows = await _repo.fetchSalesVelocity(days: days);
    final predictions = <LowStockPrediction>[];

    for (final row in rows) {
      final stock = (row['current_stock'] as num).toDouble();
      if (stock <= 0) continue;
      final sold = (row['sold_qty'] as num).toDouble();
      final dailyRate = sold / days;
      if (dailyRate <= 0) continue;

      final daysRemaining = stock / dailyRate;
      predictions.add(LowStockPrediction(
        productId: row['id'] as int,
        productName: row['name'] as String? ?? 'منتج',
        currentStock: stock,
        dailySalesRate: dailyRate,
        daysRemaining: daysRemaining,
        urgency: _classify(daysRemaining),
      ));
    }

    predictions.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    return predictions.take(30).toList();
  }

  ReorderUrgency _classify(double days) {
    if (days <= OperationsThresholds.criticalDaysRemaining) return ReorderUrgency.critical;
    if (days <= OperationsThresholds.urgentDaysRemaining) return ReorderUrgency.urgent;
    if (days <= OperationsThresholds.warningDaysRemaining) return ReorderUrgency.warning;
    return ReorderUrgency.safe;
  }

  Future<List<OperationalAlert>> evaluateAlerts() async {
    final preds = await predict();
    final now = DateTime.now();
    return preds
        .where((p) =>
            p.urgency == ReorderUrgency.critical ||
            p.urgency == ReorderUrgency.urgent)
        .take(10)
        .map((p) {
      return OperationalAlertBuilder.create(
        id: 'predict_${p.productId}',
        type: OperationalAlertType.lowStockPrediction,
        severity: p.urgency == ReorderUrgency.critical
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'تنبؤ نفاد: ${p.productName}',
        description:
            'متبقي ~${p.daysRemaining.toStringAsFixed(1)} يوم (${p.currentStock.toStringAsFixed(0)} وحدة)',
        reason:
            'معدل البيع ${p.dailySalesRate.toStringAsFixed(2)}/يوم × المخزون ${p.currentStock.toStringAsFixed(0)}',
        createdAt: now,
        entityType: 'product',
        entityId: p.productId,
        actionRoute: '/inventory',
      );
    }).toList();
  }
}