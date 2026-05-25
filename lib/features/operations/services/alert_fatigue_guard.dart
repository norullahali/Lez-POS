import '../config/operations_thresholds.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_state.dart';
import '../models/operational_alert_type.dart';
import 'alert_priority_scorer.dart';

class AlertFatigueGuard {
  AlertFatigueGuard._();

  static const _groupableTypes = {
    OperationalAlertType.lowStock,
    OperationalAlertType.deadStock,
    OperationalAlertType.overstockRisk,
    OperationalAlertType.lowStockPrediction,
    OperationalAlertType.expiryNear,
    OperationalAlertType.overdueDebt,
  };

  static List<OperationalAlert> apply(List<OperationalAlert> alerts) {
    final output = <OperationalAlert>[];
    final byType = <OperationalAlertType, List<OperationalAlert>>{};

    for (final alert in alerts) {
      if (_groupableTypes.contains(alert.type) &&
          alert.state.isVisibleInInbox &&
          !alert.isGrouped) {
        byType.putIfAbsent(alert.type, () => []).add(alert);
      } else {
        output.add(alert);
      }
    }

    for (final entry in byType.entries) {
      final items = entry.value;
      if (items.length < OperationsThresholds.groupAlertsMinCount) {
        output.addAll(items);
        continue;
      }

      final fingerprints = items.map((a) => a.fingerprint).toList();
      final maxSeverity = items
          .map((a) => a.severity)
          .reduce((a, b) => a.sortOrder <= b.sortOrder ? a : b);

      final grouped = OperationalAlert(
        id: 'group_${entry.key.name}',
        fingerprint: 'group|${entry.key.name}',
        type: entry.key,
        severity: maxSeverity,
        title: _groupTitle(entry.key, items.length),
        description: _groupDescription(items),
        reason: 'تم تجميع ${items.length} تنبيهات من نفس النوع لتقليل الضوضاء',
        createdAt: items.first.createdAt,
        lastSeenAt: DateTime.now(),
        state: OperationalAlertState.active,
        entityType: null,
        entityId: null,
        actionLabel: 'عرض المخزن',
        actionRoute: _groupRoute(entry.key),
        isGrouped: true,
        groupedCount: items.length,
        groupedFingerprints: fingerprints,
      );

      output.add(AlertPriorityScorer.enrich(grouped));
    }

    output.sort(AlertPriorityScorer.compare);
    return output;
  }

  static String _groupTitle(OperationalAlertType type, int count) {
    return switch (type) {
      OperationalAlertType.lowStock => '$count منتجات بمخزون منخفض',
      OperationalAlertType.deadStock => '$count منتجات راكدة',
      OperationalAlertType.overstockRisk => '$count منتجات بخطر تكدس',
      OperationalAlertType.lowStockPrediction => '$count تنبؤات نفاد مخزون',
      OperationalAlertType.expiryNear => '$count منتجات قرب انتهاء الصلاحية',
      OperationalAlertType.overdueDebt => '$count ذمم مستحقة',
      _ => '$count تنبيهات',
    };
  }

  static String _groupDescription(List<OperationalAlert> items) {
    final sample = items.take(3).map((a) => a.title).join(' • ');
    return sample;
  }

  static String _groupRoute(OperationalAlertType type) {
    return switch (type) {
      OperationalAlertType.overdueDebt => '/customers',
      OperationalAlertType.expiryNear => '/inventory',
      _ => '/inventory',
    };
  }
}