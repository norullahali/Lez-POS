import '../config/operations_thresholds.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'alert_builder.dart';

class SuspiciousActivityDetector {
  SuspiciousActivityDetector(this._repo);

  final OperationsIntelligenceRepository _repo;

  Future<List<OperationalAlert>> evaluate() async {
    final alerts = <OperationalAlert>[];
    final now = DateTime.now();

    final refunds = await _repo.fetchCashierRefundsToday(
      minCount: OperationsThresholds.suspiciousRefundCount,
      minAmount: OperationsThresholds.suspiciousRefundAmount,
    );
    for (final row in refunds) {
      final userId = row['user_id'] as int?;
      if (userId == null) continue;
      final count = (row['refund_count'] as int?) ?? 0;
      final amount = (row['refund_amount'] as num).toDouble();
      alerts.add(OperationalAlertBuilder.create(
        id: 'suspicious_refund_$userId',
        type: OperationalAlertType.suspiciousRefund,
        severity: count >= OperationsThresholds.suspiciousRefundCriticalCount ||
                amount >= OperationsThresholds.suspiciousRefundCriticalAmount
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'مرتجعات مرتفعة: ${row['name']}',
        description: '$count مرتجع بقيمة ${amount.toStringAsFixed(0)} اليوم',
        reason: count >= OperationsThresholds.suspiciousRefundCriticalCount
            ? 'عدد المرتجعات ($count) يتجاوز الحد (${OperationsThresholds.suspiciousRefundCriticalCount}) اليوم'
            : 'قيمة المرتجعات (${amount.toStringAsFixed(0)}) تتجاوز الحد (${OperationsThresholds.suspiciousRefundAmount.toInt()}) اليوم',
        createdAt: now,
        entityType: 'user',
        entityId: userId,
        actionLabel: 'تحليل المرتجعات',
        actionRoute: '/return-analytics',
      ));
    }

    final returnRate = await _repo.fetchReturnRateComparison();
    final todayRate = (returnRate['today_rate'] as num?)?.toDouble() ?? 0;
    final avgDaily = (returnRate['avg_daily_returns'] as num?)?.toDouble() ?? 0;
    final todayReturns = (returnRate['today_returns'] as num?)?.toDouble() ?? 0;
    if (todayReturns > avgDaily * OperationsThresholds.returnSpikeRatio &&
        todayReturns > OperationsThresholds.returnSpikeMinAmount) {
      alerts.add(OperationalAlertBuilder.create(
        id: 'high_return_rate_today',
        type: OperationalAlertType.highReturnRate,
        severity: OperationalAlertSeverity.warning,
        title: 'ارتفاع المرتجعات اليوم',
        description:
            'مرتجعات ${todayReturns.toStringAsFixed(0)} (${todayRate.toStringAsFixed(1)}% من المبيعات)',
        reason:
            'مرتجعات اليوم (${todayReturns.toStringAsFixed(0)}) أعلى من المتوسط اليومي (${avgDaily.toStringAsFixed(0)})',
        createdAt: now,
        actionRoute: '/return-analytics',
      ));
    }

    final signals = await _repo.fetchSuspiciousActivitySignals();
    for (final row in signals.take(5)) {
      final userId = row['user_id'] as int?;
      final action = row['action'] as String? ?? '';
      final cnt = (row['cnt'] as int?) ?? 0;
      alerts.add(OperationalAlertBuilder.create(
        id: 'unusual_${userId ?? 0}_$action',
        type: OperationalAlertType.unusualActivity,
        severity: cnt >= OperationsThresholds.suspiciousActionCriticalCount
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'نشاط غير اعتيادي: ${row['name'] ?? 'مستخدم'}',
        description: '$action × $cnt اليوم',
        reason: 'تكرار عملية $action ($cnt مرات) خلال اليوم',
        createdAt: now,
        entityType: 'user',
        entityId: userId,
        actionRoute: '/activity',
      ));
    }

    final criticalCount = await _repo.fetchCriticalActivityCountToday();
    if (criticalCount >= OperationsThresholds.criticalActivitySpikeCount) {
      alerts.add(OperationalAlertBuilder.create(
        id: 'critical_activity_spike',
        type: OperationalAlertType.unusualActivity,
        severity: OperationalAlertSeverity.critical,
        title: 'نشاط تحذيري مرتفع',
        description: '$criticalCount حدث تحذيري/حرج اليوم',
        reason:
            'عدد أحداث severity=warning/critical ($criticalCount) ≥ ${OperationsThresholds.criticalActivitySpikeCount} اليوم',
        createdAt: now,
        actionRoute: '/activity',
      ));
    }

    return alerts;
  }
}