import '../cache/automation_cache.dart';
import '../governance/recommendation_governance_service.dart';
import '../models/automation_audit_context.dart';
import '../models/workflow_action.dart';
import '../models/workflow_definition.dart';
import '../models/workflow_execution_result.dart';
import '../models/workflow_trigger.dart';
import '../models/debt_follow_up_item.dart';
import '../models/reorder_suggestion.dart';
import '../services/debt_follow_up_service.dart';
import '../services/reorder_suggestion_service.dart';
import '../../operations/models/cashier_behavior_models.dart';
import '../../operations/models/operational_alert.dart';

class WorkflowEngineService {
  WorkflowEngineService({
    required ReorderSuggestionService reorder,
    required DebtFollowUpService debt,
    RecommendationGovernanceService? governance,
  })  : _reorder = reorder,
        _debt = debt,
        _governance = governance ?? RecommendationGovernanceService();

  final ReorderSuggestionService _reorder;
  final DebtFollowUpService _debt;
  final RecommendationGovernanceService _governance;

  Future<WorkflowEvaluationBundle> evaluate({
    List<OperationalAlert>? alerts,
    List<CashierBehaviorRow>? cashiers,
  }) async {
    return AutomationCache.memo('workflow_eval_v1', () async {
      final now = DateTime.now();
      final results = <WorkflowExecutionResult>[];
      final definitions = <WorkflowDefinition>[];

      final reorders = await _reorder.generate();
      final critical = reorders.where((r) => r.urgency == ReorderUrgency.critical).take(3).toList();
      if (critical.isNotEmpty) {
        const workflowId = 'wf_critical_reorder';
        final def = WorkflowDefinition(
          id: workflowId,
          titleAr: 'إعادة تخزين عاجلة',
          triggers: critical
              .map((c) => WorkflowTrigger(
                    type: WorkflowTriggerType.criticalStock,
                    description: '${c.productName}: ${c.explanation}',
                    entityId: c.productId,
                    entityType: 'product',
                  ))
              .toList(),
          actions: const [
            WorkflowAction(kind: WorkflowActionKind.suggestReorder, labelAr: 'مراجعة طلب الشراء', route: '/purchases/new'),
            WorkflowAction(kind: WorkflowActionKind.reviewInventory, labelAr: 'عرض المخزن', route: '/inventory'),
          ],
        );
        definitions.add(def);
        results.add(WorkflowExecutionResult(
          workflowId: workflowId,
          status: WorkflowExecutionStatus.suggested,
          executedAt: now,
          summaryAr: '${critical.length} منتجات تحتاج إعادة تخزين عاجلة',
          actions: def.actions,
          reason: critical.first.explanation,
          fingerprint: 'wf|$workflowId',
          audit: AutomationAuditContext(
            whyGenerated: critical.first.explanation,
            sourceEngine: AutomationSourceEngine.workflow,
            heuristicExplanation: 'مخزون حرج مع velocity مرتفع',
            triggerSource: WorkflowTriggerType.criticalStock.name,
            sourceMetrics: {'count': critical.length},
            confidence: HeuristicConfidence.high,
          ),
        ));
      }

      if (cashiers != null) {
        for (final c in cashiers.take(3)) {
          final workflowId = 'wf_cashier_${c.userId}';
          final def = WorkflowDefinition(
            id: workflowId,
            titleAr: 'مراجعة كاشير',
            triggers: [
              WorkflowTrigger(
                type: WorkflowTriggerType.excessiveRefunds,
                description: c.flags.join('، '),
                entityId: c.userId,
                entityType: 'user',
              ),
            ],
            actions: const [
              WorkflowAction(kind: WorkflowActionKind.reviewCashier, labelAr: 'الجدول الزمني', route: '/activity/timeline'),
            ],
          );
          definitions.add(def);
          results.add(WorkflowExecutionResult(
            workflowId: workflowId,
            status: WorkflowExecutionStatus.suggested,
            executedAt: now,
            summaryAr: 'سلوك غير اعتيادي: ${c.name}',
            actions: def.actions,
            reason: c.flags.join(' • '),
            fingerprint: 'wf|$workflowId',
            audit: AutomationAuditContext(
              whyGenerated: c.flags.join(' • '),
              sourceEngine: AutomationSourceEngine.workflow,
              heuristicExplanation: 'مرتجعات/خصومات فوق العتبة',
              triggerSource: WorkflowTriggerType.excessiveRefunds.name,
              sourceMetrics: {'userId': c.userId},
              confidence: HeuristicConfidence.medium,
            ),
          ));
        }
      }

      final debts = await _debt.generate();
      if (debts.any((d) => d.riskLevel == DebtRiskLevel.critical)) {
        const workflowId = 'wf_debt_critical';
        final top = debts.first;
        final def = WorkflowDefinition(
          id: workflowId,
          titleAr: 'متابعة ذمم حرجة',
          triggers: [
            WorkflowTrigger(
              type: WorkflowTriggerType.overdueDebt,
              description: top.explanation,
              entityId: top.partyId,
              entityType: top.partyType.name,
            ),
          ],
          actions: [
            WorkflowAction(
              kind: WorkflowActionKind.followUpDebt,
              labelAr: 'فتح الملف',
              route: top.actionRoute ?? '/customers',
            ),
          ],
        );
        definitions.add(def);
        results.add(WorkflowExecutionResult(
          workflowId: workflowId,
          status: WorkflowExecutionStatus.suggested,
          executedAt: now,
          summaryAr: 'ذمة حرجة: ${top.partyName}',
          actions: def.actions,
          reason: top.explanation,
          fingerprint: 'wf|$workflowId|${top.partyType.name}:${top.partyId}',
          audit: AutomationAuditContext(
            whyGenerated: top.explanation,
            sourceEngine: AutomationSourceEngine.workflow,
            heuristicExplanation: 'رصيد ذمة فوق عتبة الخطورة',
            triggerSource: WorkflowTriggerType.overdueDebt.name,
            sourceMetrics: {'balance': top.balance, 'partyId': top.partyId},
            confidence: HeuristicConfidence.high,
          ),
        ));
      }

      return _governance.governWorkflows(WorkflowEvaluationBundle(results: results, definitions: definitions));
    });
  }
}
