import '../models/operational_alert.dart';
import '../models/operational_alert_type.dart';

class AlertFingerprint {
  AlertFingerprint._();

  static String compute({
    required OperationalAlertType type,
    required String id,
    String? entityType,
    int? entityId,
  }) {
    if (entityType != null && entityId != null) {
      return '${type.name}|$entityType|$entityId';
    }
    return id;
  }

  static String fromAlert(OperationalAlert alert) {
    return compute(
      type: alert.type,
      id: alert.id,
      entityType: alert.entityType,
      entityId: alert.entityId,
    );
  }
}