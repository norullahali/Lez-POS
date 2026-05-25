import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../models/operational_impact_level.dart';

class AlertPriorityScorer {
  AlertPriorityScorer._();

  static OperationalAlert enrich(OperationalAlert alert) {
    final urgency = _urgencyScore(alert);
    final impact = _impactLevel(alert);
    final priority = (urgency + _impactWeight(impact) + _severityWeight(alert.severity))
        .clamp(0, 100);
    return alert.copyWith(
      priorityScore: priority,
      urgencyScore: urgency,
      impactLevel: impact,
    );
  }

  static int compare(OperationalAlert a, OperationalAlert b) {
    final p = b.priorityScore.compareTo(a.priorityScore);
    if (p != 0) return p;
    final i = a.impactLevel.sortOrder.compareTo(b.impactLevel.sortOrder);
    if (i != 0) return i;
    final s = a.severity.sortOrder.compareTo(b.severity.sortOrder);
    if (s != 0) return s;
    return (b.lastSeenAt ?? b.createdAt).compareTo(a.lastSeenAt ?? a.createdAt);
  }

  static int _urgencyScore(OperationalAlert alert) {
    return switch (alert.type) {
      OperationalAlertType.lowStock => alert.severity == OperationalAlertSeverity.critical ? 35 : 25,
      OperationalAlertType.lowStockPrediction => 30,
      OperationalAlertType.expiryCritical => 35,
      OperationalAlertType.expiryNear => 20,
      OperationalAlertType.sessionMismatch => 28,
      OperationalAlertType.suspiciousRefund => 26,
      OperationalAlertType.highReturnRate => 22,
      OperationalAlertType.cashierAnomaly => 18,
      OperationalAlertType.overdueDebt => 20,
      OperationalAlertType.weakSales => 15,
      OperationalAlertType.deadStock => 12,
      OperationalAlertType.overstockRisk => 8,
      OperationalAlertType.unusualActivity => 24,
      OperationalAlertType.inventoryMismatch => 20,
    };
  }

  static OperationalImpactLevel _impactLevel(OperationalAlert alert) {
    if (alert.severity == OperationalAlertSeverity.critical) {
      return OperationalImpactLevel.critical;
    }
    return switch (alert.type) {
      OperationalAlertType.lowStock ||
      OperationalAlertType.expiryCritical ||
      OperationalAlertType.sessionMismatch =>
        OperationalImpactLevel.high,
      OperationalAlertType.weakSales ||
      OperationalAlertType.highReturnRate ||
      OperationalAlertType.suspiciousRefund =>
        OperationalImpactLevel.medium,
      _ => OperationalImpactLevel.low,
    };
  }

  static int _impactWeight(OperationalImpactLevel level) {
    return switch (level) {
      OperationalImpactLevel.critical => 30,
      OperationalImpactLevel.high => 22,
      OperationalImpactLevel.medium => 14,
      OperationalImpactLevel.low => 6,
    };
  }

  static int _severityWeight(OperationalAlertSeverity severity) {
    return switch (severity) {
      OperationalAlertSeverity.critical => 25,
      OperationalAlertSeverity.warning => 15,
      OperationalAlertSeverity.info => 5,
    };
  }
}