import 'automation_audit_context.dart';
import 'workflow_action.dart';
import 'workflow_definition.dart';
import 'workflow_lifecycle_state.dart';

enum WorkflowExecutionStatus { suggested, skipped, logged }

class WorkflowExecutionResult {
  const WorkflowExecutionResult({
    required this.workflowId,
    required this.status,
    required this.executedAt,
    required this.summaryAr,
    this.actions = const [],
    this.reason,
    this.lifecycleState = WorkflowLifecycleState.pending,
    this.priorityScore = 0,
    this.fingerprint,
    this.audit,
  });
  final String workflowId;
  final WorkflowExecutionStatus status;
  final DateTime executedAt;
  final String summaryAr;
  final List<WorkflowAction> actions;
  final String? reason;
  final WorkflowLifecycleState lifecycleState;
  final int priorityScore;
  final String? fingerprint;
  final AutomationAuditContext? audit;
}

class WorkflowEvaluationBundle {
  const WorkflowEvaluationBundle({required this.results, required this.definitions});
  final List<WorkflowExecutionResult> results;
  final List<WorkflowDefinition> definitions;
}
