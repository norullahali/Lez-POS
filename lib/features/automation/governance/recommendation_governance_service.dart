import '../models/automation_audit_context.dart';
import '../models/business_guidance_item.dart';
import '../models/smart_action_group.dart';
import '../models/smart_action_item.dart';
import '../models/workflow_execution_result.dart';
import '../models/workflow_lifecycle_state.dart';
import 'automation_priority_engine.dart';
import 'recommendation_deduplication_service.dart';
import 'recommendation_fingerprint.dart';
import 'workflow_conflict_detector.dart';
import 'workflow_history_service.dart';

class RecommendationGovernanceService {
  RecommendationGovernanceService({WorkflowHistoryService? history}) : _history = history;
  final WorkflowHistoryService? _history;

  Future<List<BusinessGuidanceItem>> governGuidance(List<BusinessGuidanceItem> raw) async {
    final governed = <BusinessGuidanceItem>[];
    for (final item in raw) {
      final fingerprint = item.fingerprint ?? 'assistant|${item.id}';
      final audit = item.audit ??
          AutomationAuditContext(
            whyGenerated: item.whyDetected,
            sourceEngine: AutomationSourceEngine.assistant,
            heuristicExplanation: item.nextStep,
            triggerSource: item.id,
            sourceMetrics: const {},
            confidence: item.severity == GuidanceSeverity.warning
                ? HeuristicConfidence.high
                : HeuristicConfidence.medium,
          );
      final merge = await RecommendationDeduplicationService.merge(
        fingerprint: fingerprint,
        kind: item.id,
        sourceEngine: AutomationSourceEngine.assistant,
        whyGenerated: audit.whyGenerated,
        heuristicExplanation: audit.heuristicExplanation,
        triggerSource: audit.triggerSource,
        policy: RecommendationDeduplicationService.policyForEngine(AutomationSourceEngine.assistant),
        sourceMetrics: audit.sourceMetrics,
        confidence: audit.confidence,
        titleSnapshot: item.whatHappened,
      );
      if (merge.suppressed || !merge.record.lifecycleState.isVisible) continue;
      governed.add(
        AutomationPriorityEngine.applyToGuidance(
          BusinessGuidanceItem(
            id: item.id,
            whatHappened: item.whatHappened,
            whyDetected: item.whyDetected,
            nextStep: item.nextStep,
            severity: item.severity,
            actionRoute: item.actionRoute,
            audit: audit,
            fingerprint: fingerprint,
            occurrenceCount: merge.record.occurrenceCount,
            lastRefreshedAt: merge.record.lastRefreshedAt,
          ),
        ),
      );
    }
    governed.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return governed;
  }

  Future<List<SmartActionItem>> governActions(List<SmartActionItem> raw) async {
    final governed = <SmartActionItem>[];
    for (final action in raw) {
      final engine = _engineFor(action);
      final fingerprint = RecommendationFingerprint.forAction(action);
      final audit = action.audit ??
          AutomationAuditContext(
            whyGenerated: action.reason,
            sourceEngine: engine,
            heuristicExplanation: action.recommendation,
            triggerSource: action.category.name,
            sourceMetrics: {
              if (action.entityId != null) 'entityId': action.entityId,
              if (action.entityType != null) 'entityType': action.entityType,
            },
          );
      final merge = await RecommendationDeduplicationService.merge(
        fingerprint: fingerprint,
        kind: action.category.name,
        sourceEngine: engine,
        whyGenerated: audit.whyGenerated,
        heuristicExplanation: audit.heuristicExplanation,
        triggerSource: audit.triggerSource,
        policy: RecommendationDeduplicationService.policyForEngine(engine),
        sourceMetrics: audit.sourceMetrics,
        confidence: audit.confidence,
        titleSnapshot: action.title,
        entityType: action.entityType,
        entityId: action.entityId,
      );
      if (merge.suppressed) continue;
      final record = merge.record;
      if (!record.lifecycleState.isVisible) continue;

      governed.add(
        AutomationPriorityEngine.applyToAction(
          SmartActionItem(
            id: action.id,
            title: action.title,
            reason: action.reason,
            recommendation: action.recommendation,
            severity: action.severity,
            category: action.category,
            priorityScore: action.priorityScore,
            actionRoute: action.actionRoute,
            actionLabel: action.actionLabel,
            entityType: action.entityType,
            entityId: action.entityId,
            requiresApproval: action.requiresApproval,
            fingerprint: fingerprint,
            lifecycleState: record.lifecycleState,
            audit: audit,
            group: _groupFor(action),
            expiresAt: record.expiresAt,
            occurrenceCount: record.occurrenceCount,
            lastRefreshedAt: record.lastRefreshedAt,
          ),
        ),
      );
    }

    final conflicts = WorkflowConflictDetector.detect(governed);
    if (conflicts.isEmpty) {
      governed.sort(SmartActionItem.compare);
      return governed;
    }

    final withConflicts = governed.map((a) {
      final itemConflicts = WorkflowConflictDetector.forAction(a.fingerprint ?? a.id, conflicts);
      return SmartActionItem(
        id: a.id,
        title: a.title,
        reason: a.reason,
        recommendation: itemConflicts.isNotEmpty
            ? '${a.recommendation} (تعارض: ${itemConflicts.first.resolutionHintAr})'
            : a.recommendation,
        severity: a.severity,
        category: a.category,
        priorityScore: a.priorityScore,
        actionRoute: a.actionRoute,
        actionLabel: a.actionLabel,
        entityType: a.entityType,
        entityId: a.entityId,
        requiresApproval: a.requiresApproval,
        fingerprint: a.fingerprint,
        lifecycleState: a.lifecycleState,
        audit: a.audit,
        group: a.group,
        conflicts: itemConflicts,
        expiresAt: a.expiresAt,
        occurrenceCount: a.occurrenceCount,
        lastRefreshedAt: a.lastRefreshedAt,
      );
    }).toList()
      ..sort(SmartActionItem.compare);
    return withConflicts;
  }

  Future<WorkflowEvaluationBundle> governWorkflows(WorkflowEvaluationBundle bundle) async {
    final results = <WorkflowExecutionResult>[];
    for (final result in bundle.results) {
      final fingerprint = result.fingerprint ?? 'wf|${result.workflowId}';
      await _history?.recordGeneration(
        workflowId: result.workflowId,
        fingerprint: fingerprint,
        whyGenerated: result.reason ?? result.summaryAr,
        sourceEngine: 'workflow',
        triggerSource: result.workflowId,
      );
      results.add(
        AutomationPriorityEngine.applyToWorkflow(
          WorkflowExecutionResult(
            workflowId: result.workflowId,
            status: result.status,
            executedAt: result.executedAt,
            summaryAr: result.summaryAr,
            actions: result.actions,
            reason: result.reason,
            lifecycleState: result.lifecycleState,
            fingerprint: fingerprint,
            audit: result.audit,
          ),
        ),
      );
    }
    return WorkflowEvaluationBundle(results: results, definitions: bundle.definitions);
  }

  static AutomationSourceEngine _engineFor(SmartActionItem action) => switch (action.category) {
        SmartActionCategory.reorder => AutomationSourceEngine.reorder,
        SmartActionCategory.purchase => AutomationSourceEngine.purchase,
        SmartActionCategory.restock => AutomationSourceEngine.restock,
        SmartActionCategory.debt => AutomationSourceEngine.debt,
        SmartActionCategory.loyalty => AutomationSourceEngine.loyalty,
        SmartActionCategory.cashier => AutomationSourceEngine.cashier,
        SmartActionCategory.sales => AutomationSourceEngine.assistant,
        SmartActionCategory.workflow => AutomationSourceEngine.alert,
      };

  static SmartActionGroup _groupFor(SmartActionItem action) {
    if (action.id.startsWith('alert_')) return SmartActionGroup.alerts;
    return SmartActionGroupX.fromCategory(action.category);
  }

}