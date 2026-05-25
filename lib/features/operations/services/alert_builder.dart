import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import 'alert_fingerprint.dart';

class OperationalAlertBuilder {
  OperationalAlertBuilder._();

  static OperationalAlert create({
    required String id,
    required OperationalAlertType type,
    required OperationalAlertSeverity severity,
    required String title,
    required String description,
    required String reason,
    required DateTime createdAt,
    String? entityType,
    int? entityId,
    String? actionLabel,
    String? actionRoute,
  }) {
    return OperationalAlert(
      id: id,
      fingerprint: AlertFingerprint.compute(
        type: type,
        id: id,
        entityType: entityType,
        entityId: entityId,
      ),
      type: type,
      severity: severity,
      title: title,
      description: description,
      reason: reason,
      createdAt: createdAt,
      lastSeenAt: createdAt,
      entityType: entityType,
      entityId: entityId,
      actionLabel: actionLabel,
      actionRoute: actionRoute,
    );
  }
}