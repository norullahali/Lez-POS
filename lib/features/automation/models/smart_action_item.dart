import 'automation_audit_context.dart';
import 'smart_action_group.dart';
import 'workflow_conflict.dart';
import 'workflow_lifecycle_state.dart';

enum SmartActionSeverity { info, warning, critical }

enum SmartActionCategory {
  reorder,
  purchase,
  restock,
  debt,
  loyalty,
  cashier,
  sales,
  workflow,
}

class SmartActionItem {
  const SmartActionItem({
    required this.id,
    required this.title,
    required this.reason,
    required this.recommendation,
    required this.severity,
    required this.category,
    required this.priorityScore,
    this.actionRoute,
    this.actionLabel,
    this.entityType,
    this.entityId,
    this.requiresApproval = true,
    this.fingerprint,
    this.lifecycleState = WorkflowLifecycleState.pending,
    this.audit,
    this.group,
    this.conflicts = const [],
    this.expiresAt,
    this.occurrenceCount = 1,
    this.lastRefreshedAt,
  });

  final String id;
  final String title;
  final String reason;
  final String recommendation;
  final SmartActionSeverity severity;
  final SmartActionCategory category;
  final int priorityScore;
  final String? actionRoute;
  final String? actionLabel;
  final String? entityType;
  final int? entityId;
  final bool requiresApproval;
  final String? fingerprint;
  final WorkflowLifecycleState lifecycleState;
  final AutomationAuditContext? audit;
  final SmartActionGroup? group;
  final List<WorkflowConflict> conflicts;
  final DateTime? expiresAt;
  final int occurrenceCount;
  final DateTime? lastRefreshedAt;

  static int compare(SmartActionItem a, SmartActionItem b) {
    final s = _sev(a.severity).compareTo(_sev(b.severity));
    if (s != 0) return s;
    return b.priorityScore.compareTo(a.priorityScore);
  }

  static int _sev(SmartActionSeverity s) => switch (s) {
        SmartActionSeverity.critical => 0,
        SmartActionSeverity.warning => 1,
        SmartActionSeverity.info => 2,
      };
}
