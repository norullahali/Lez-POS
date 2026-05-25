import '../config/operations_thresholds.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_state.dart';
import 'alert_fingerprint.dart';
import 'alert_lifecycle_store.dart';
import 'alert_priority_scorer.dart';

class AlertDeduplicationService {
  AlertDeduplicationService._();

  static Future<List<OperationalAlert>> process(List<OperationalAlert> raw) async {
    final records = await AlertLifecycleStore.loadRecords();
    final now = DateTime.now();
    final merged = <String, OperationalAlert>{};

    for (final incoming in raw) {
      final fingerprint = incoming.fingerprint.isNotEmpty
          ? incoming.fingerprint
          : AlertFingerprint.fromAlert(incoming);
      final existingRecord = records[fingerprint];
      final existingAlert = merged[fingerprint];

      final severity = _maxSeverity(
        existingAlert?.severity,
        incoming.severity,
      );

      final occurrence = (existingRecord?.occurrenceCount ?? existingAlert?.occurrenceCount ?? 0) + 1;
      final firstSeen = existingRecord?.firstSeenAt ?? incoming.createdAt;
      var state = existingRecord?.state ?? OperationalAlertState.active;

      final severityEscalated = existingRecord?.previousSeverity != null &&
          severity.name != existingRecord!.previousSeverity;

      final inCooldown = existingRecord?.lastNotifiedAt != null &&
          now.difference(existingRecord!.lastNotifiedAt!).inMinutes <
              OperationsThresholds.alertCooldownMinutes &&
          !severityEscalated;

      if (inCooldown && state == OperationalAlertState.active) {
        state = OperationalAlertState.acknowledged;
      } else if (state == OperationalAlertState.archived ||
          state == OperationalAlertState.resolved) {
        // preserve terminal states
      } else if (!inCooldown) {
        state = OperationalAlertState.active;
      }

      final alert = OperationalAlert(
        id: incoming.id,
        fingerprint: fingerprint,
        type: incoming.type,
        severity: severity,
        title: incoming.title,
        description: incoming.description,
        reason: incoming.reason,
        createdAt: firstSeen,
        lastSeenAt: now,
        state: state,
        occurrenceCount: occurrence,
        entityType: incoming.entityType,
        entityId: incoming.entityId,
        actionLabel: incoming.actionLabel,
        actionRoute: incoming.actionRoute,
        isDismissed: state == OperationalAlertState.archived ||
            state == OperationalAlertState.resolved,
        isGrouped: incoming.isGrouped,
        groupedCount: incoming.groupedCount,
        groupedFingerprints: incoming.groupedFingerprints,
      );

      merged[fingerprint] = AlertPriorityScorer.enrich(alert);

      records[fingerprint] = AlertLifecycleRecord(
        fingerprint: fingerprint,
        state: state,
        firstSeenAt: firstSeen,
        lastSeenAt: now,
        occurrenceCount: occurrence,
        lastNotifiedAt: inCooldown ? existingRecord.lastNotifiedAt : now,
        previousSeverity: severity.name,
      );
    }

    await AlertLifecycleStore.saveRecords(records);
    return merged.values.toList();
  }

  static OperationalAlertSeverity _maxSeverity(
    OperationalAlertSeverity? a,
    OperationalAlertSeverity b,
  ) {
    if (a == null) return b;
    return a.sortOrder <= b.sortOrder ? a : b;
  }
}