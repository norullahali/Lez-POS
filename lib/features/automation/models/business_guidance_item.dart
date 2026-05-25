import 'automation_audit_context.dart';

enum GuidanceSeverity { info, warning, positive }

class BusinessGuidanceItem {
  const BusinessGuidanceItem({
    required this.id,
    required this.whatHappened,
    required this.whyDetected,
    required this.nextStep,
    required this.severity,
    this.actionRoute,
    this.priorityScore = 50,
    this.audit,
    this.fingerprint,
    this.occurrenceCount = 1,
    this.lastRefreshedAt,
  });
  final String id;
  final String whatHappened;
  final String whyDetected;
  final String nextStep;
  final GuidanceSeverity severity;
  final String? actionRoute;
  final int priorityScore;
  final AutomationAuditContext? audit;
  final String? fingerprint;
  final int occurrenceCount;
  final DateTime? lastRefreshedAt;
}
