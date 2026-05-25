import '../models/automation_audit_context.dart';
import '../models/business_guidance_item.dart';
import '../models/smart_action_item.dart';
import '../models/workflow_execution_result.dart';

class AutomationPriorityEngine {
  AutomationPriorityEngine._();

  static int scoreAction({
    required SmartActionSeverity severity,
    required int baseScore,
    required HeuristicConfidence confidence,
    required DateTime? lastRefreshedAt,
    required int occurrenceCount,
    required double financialImpact,
  }) {
    final urgency = switch (severity) {
      SmartActionSeverity.critical => 40,
      SmartActionSeverity.warning => 25,
      SmartActionSeverity.info => 10,
    };
    final confidenceBoost = switch (confidence) {
      HeuristicConfidence.high => 12,
      HeuristicConfidence.medium => 6,
      HeuristicConfidence.low => 0,
    };
    final freshness = _freshnessBoost(lastRefreshedAt);
    final repeatPenalty = occurrenceCount > 3 ? (occurrenceCount - 3) * 2 : 0;
    final financial = (financialImpact.clamp(0, 500) / 10).round();
    return (baseScore + urgency + confidenceBoost + freshness + financial - repeatPenalty).clamp(1, 100);
  }

  static SmartActionItem applyToAction(SmartActionItem action) {
    final audit = action.audit;
    return SmartActionItem(
      id: action.id,
      title: action.title,
      reason: action.reason,
      recommendation: action.recommendation,
      severity: action.severity,
      category: action.category,
      priorityScore: scoreAction(
        severity: action.severity,
        baseScore: action.priorityScore,
        confidence: audit?.confidence ?? HeuristicConfidence.medium,
        lastRefreshedAt: action.lastRefreshedAt,
        occurrenceCount: action.occurrenceCount,
        financialImpact: _financialImpact(action),
      ),
      actionRoute: action.actionRoute,
      actionLabel: action.actionLabel,
      entityType: action.entityType,
      entityId: action.entityId,
      requiresApproval: action.requiresApproval,
      fingerprint: action.fingerprint,
      lifecycleState: action.lifecycleState,
      audit: action.audit,
      group: action.group,
      conflicts: action.conflicts,
      expiresAt: action.expiresAt,
      occurrenceCount: action.occurrenceCount,
      lastRefreshedAt: action.lastRefreshedAt,
    );
  }

  static BusinessGuidanceItem applyToGuidance(BusinessGuidanceItem item) {
    final base = switch (item.severity) {
      GuidanceSeverity.warning => 70,
      GuidanceSeverity.positive => 40,
      GuidanceSeverity.info => 50,
    };
    final score = scoreAction(
      severity: item.severity == GuidanceSeverity.warning
          ? SmartActionSeverity.warning
          : SmartActionSeverity.info,
      baseScore: base,
      confidence: item.audit?.confidence ?? HeuristicConfidence.medium,
      lastRefreshedAt: item.lastRefreshedAt,
      occurrenceCount: item.occurrenceCount,
      financialImpact: item.audit?.sourceMetrics['financialImpact'] as double? ?? 0,
    );
    return BusinessGuidanceItem(
      id: item.id,
      whatHappened: item.whatHappened,
      whyDetected: item.whyDetected,
      nextStep: item.nextStep,
      severity: item.severity,
      actionRoute: item.actionRoute,
      priorityScore: score,
      audit: item.audit,
      fingerprint: item.fingerprint,
      occurrenceCount: item.occurrenceCount,
      lastRefreshedAt: item.lastRefreshedAt,
    );
  }

  static WorkflowExecutionResult applyToWorkflow(WorkflowExecutionResult result) {
    final score = scoreAction(
      severity: SmartActionSeverity.warning,
      baseScore: 75,
      confidence: HeuristicConfidence.medium,
      lastRefreshedAt: result.executedAt,
      occurrenceCount: 1,
      financialImpact: 0,
    );
    return WorkflowExecutionResult(
      workflowId: result.workflowId,
      status: result.status,
      executedAt: result.executedAt,
      summaryAr: result.summaryAr,
      actions: result.actions,
      reason: result.reason,
      lifecycleState: result.lifecycleState,
      priorityScore: score,
      fingerprint: result.fingerprint,
      audit: result.audit,
    );
  }

  static int _freshnessBoost(DateTime? at) {
    if (at == null) return 5;
    final hours = DateTime.now().difference(at).inHours;
    if (hours <= 6) return 10;
    if (hours <= 24) return 5;
    if (hours <= 72) return 0;
    return -5;
  }

  static double _financialImpact(SmartActionItem action) => switch (action.category) {
        SmartActionCategory.debt => 200,
        SmartActionCategory.purchase => 150,
        SmartActionCategory.reorder => 100,
        _ => 30,
      };
}