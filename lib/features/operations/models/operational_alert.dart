import 'operational_alert_severity.dart';
import 'operational_alert_state.dart';
import 'operational_alert_type.dart';
import 'operational_impact_level.dart';

class OperationalAlert {
  const OperationalAlert({
    required this.id,
    required this.fingerprint,
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    required this.reason,
    required this.createdAt,
    this.lastSeenAt,
    this.state = OperationalAlertState.active,
    this.priorityScore = 0,
    this.urgencyScore = 0,
    this.impactLevel = OperationalImpactLevel.medium,
    this.occurrenceCount = 1,
    this.entityType,
    this.entityId,
    this.actionLabel,
    this.actionRoute,
    this.isDismissed = false,
    this.isGrouped = false,
    this.groupedCount = 1,
    this.groupedFingerprints = const [],
  });

  final String id;
  final String fingerprint;
  final OperationalAlertType type;
  final OperationalAlertSeverity severity;
  final String title;
  final String description;
  final String reason;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final OperationalAlertState state;
  final int priorityScore;
  final int urgencyScore;
  final OperationalImpactLevel impactLevel;
  final int occurrenceCount;
  final String? entityType;
  final int? entityId;
  final String? actionLabel;
  final String? actionRoute;
  final bool isDismissed;
  final bool isGrouped;
  final int groupedCount;
  final List<String> groupedFingerprints;

  bool get isUnread => state.countsAsUnread && !isDismissed;

  OperationalAlert copyWith({
    OperationalAlertState? state,
    bool? isDismissed,
    DateTime? lastSeenAt,
    int? occurrenceCount,
    int? priorityScore,
    int? urgencyScore,
    OperationalImpactLevel? impactLevel,
    String? title,
    String? description,
    String? reason,
  }) {
    return OperationalAlert(
      id: id,
      fingerprint: fingerprint,
      type: type,
      severity: severity,
      title: title ?? this.title,
      description: description ?? this.description,
      reason: reason ?? this.reason,
      createdAt: createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      state: state ?? this.state,
      priorityScore: priorityScore ?? this.priorityScore,
      urgencyScore: urgencyScore ?? this.urgencyScore,
      impactLevel: impactLevel ?? this.impactLevel,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      entityType: entityType,
      entityId: entityId,
      actionLabel: actionLabel,
      actionRoute: actionRoute,
      isDismissed: isDismissed ?? this.isDismissed,
      isGrouped: isGrouped,
      groupedCount: groupedCount,
      groupedFingerprints: groupedFingerprints,
    );
  }
}