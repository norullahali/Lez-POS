import 'workflow_action.dart';
import 'workflow_trigger.dart';

class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.titleAr,
    required this.triggers,
    required this.actions,
  });
  final String id;
  final String titleAr;
  final List<WorkflowTrigger> triggers;
  final List<WorkflowAction> actions;
}