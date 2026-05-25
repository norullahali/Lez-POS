import '../governance/recommendation_governance_service.dart';
import '../cache/automation_cache.dart';
import '../models/reorder_suggestion.dart';
import '../models/restock_plan_item.dart';
import '../models/smart_action_item.dart';
import '../models/debt_follow_up_item.dart';
import '../workflows/workflow_engine_service.dart';
import 'customer_loyalty_engine.dart';
import 'debt_follow_up_service.dart';
import 'purchase_recommendation_service.dart';
import 'reorder_suggestion_service.dart';
import 'restock_planning_service.dart';
import '../../operations/models/cashier_behavior_models.dart';
import '../../operations/models/operational_alert.dart';
import '../../operations/models/operational_alert_severity.dart';

class SmartActionCenterService {
  SmartActionCenterService({
    required ReorderSuggestionService reorder,
    required PurchaseRecommendationService purchase,
    required RestockPlanningService restock,
    required DebtFollowUpService debt,
    required CustomerLoyaltyEngine loyalty,
    required WorkflowEngineService workflow,
    RecommendationGovernanceService? governance,
  })  : _reorder = reorder,
        _purchase = purchase,
        _restock = restock,
        _debt = debt,
        _loyalty = loyalty,
        _workflow = workflow,
        _governance = governance ?? RecommendationGovernanceService();

  final ReorderSuggestionService _reorder;
  final PurchaseRecommendationService _purchase;
  final RestockPlanningService _restock;
  final DebtFollowUpService _debt;
  final CustomerLoyaltyEngine _loyalty;
  final WorkflowEngineService _workflow;
  final RecommendationGovernanceService _governance;

  Future<List<SmartActionItem>> buildActions({
    List<OperationalAlert>? alerts,
    List<CashierBehaviorRow>? cashiers,
  }) async {
    return AutomationCache.memo('smart_actions_v1', () async {
      final actions = <SmartActionItem>[];
      final reorders = await _reorder.generate();
      final urgent = reorders.where((r) => r.urgency != ReorderUrgency.safe).toList();
      if (urgent.length >= 3) {
        actions.add(SmartActionItem(
          id: 'group_reorder',
          title: 'طلب شراء مقترح لـ ${urgent.length} منتج',
          reason: 'مخزون منخفض مع velocity مرتفع',
          recommendation: 'راجع قائمة إعادة الطلب واعد فاتورة شراء',
          severity: SmartActionSeverity.warning,
          category: SmartActionCategory.reorder,
          priorityScore: 85,
          actionRoute: '/purchases/new',
          actionLabel: 'فاتورة شراء',
        ));
      }
      for (final r in urgent.take(5)) {
        actions.add(SmartActionItem(
          id: 'reorder_${r.productId}',
          title: 'إعادة طلب: ${r.productName}',
          reason: r.explanation,
          recommendation: 'كمية مقترحة: ${r.suggestedQty.toStringAsFixed(0)}',
          severity: r.urgency == ReorderUrgency.critical ? SmartActionSeverity.critical : SmartActionSeverity.warning,
          category: SmartActionCategory.reorder,
          priorityScore: r.priorityScore,
          actionRoute: '/inventory',
          entityType: 'product',
          entityId: r.productId,
        ));
      }

      final purchases = await _purchase.generate();
      if (purchases.isNotEmpty) {
        final top = purchases.first;
        actions.add(SmartActionItem(
          id: 'purchase_${top.supplierId ?? 0}',
          title: 'توصية شراء: ${top.supplierName}',
          reason: '${top.lines.length} منتج — تغطية ~${top.projectedCoverageDays.toStringAsFixed(0)} يوم',
          recommendation: 'راجع المورد وخطط الشراء',
          severity: SmartActionSeverity.info,
          category: SmartActionCategory.purchase,
          priorityScore: 65,
          actionRoute: '/purchases/new',
        ));
      }

      final restockPlan = await _restock.buildPlan();
      final criticalRestock = restockPlan.where((r) => r.pressure == RestockPressure.critical).toList();
      if (criticalRestock.length >= 2) {
        actions.add(SmartActionItem(
          id: 'group_restock',
          title: '${criticalRestock.length} منتجات تحتاج إعادة تخزين عاجلة',
          reason: 'ضغط مخزني مرتفع مع velocity نشط',
          recommendation: 'راجع لوحة إعادة التخزين ورتّب الجدول',
          severity: SmartActionSeverity.critical,
          category: SmartActionCategory.restock,
          priorityScore: 88,
          actionRoute: '/inventory',
        ));
      }

      final debts = await _debt.generate();
      for (final d in debts.take(5)) {
        actions.add(SmartActionItem(
          id: 'debt_${d.partyType.name}_${d.partyId}',
          title: d.partyType == DebtPartyType.customer ? 'ذمة: ${d.partyName}' : 'مورد: ${d.partyName}',
          reason: d.explanation,
          recommendation: d.suggestedFollowUpAr,
          severity: d.riskLevel == DebtRiskLevel.critical ? SmartActionSeverity.critical : SmartActionSeverity.warning,
          category: SmartActionCategory.debt,
          priorityScore: d.priorityScore,
          actionRoute: d.actionRoute,
          entityType: d.partyType.name,
          entityId: d.partyId,
        ));
      }

      final loyalty = await _loyalty.generateInsights();
      for (final l in loyalty.take(5)) {
        actions.add(SmartActionItem(
          id: 'loyalty_${l.customerId}_${l.type.name}',
          title: l.message,
          reason: 'تحليل ولاء محلي',
          recommendation: l.recommendation,
          severity: SmartActionSeverity.info,
          category: SmartActionCategory.loyalty,
          priorityScore: l.priorityScore,
          actionRoute: l.actionRoute,
          entityType: 'customer',
          entityId: l.customerId,
        ));
      }

      if (cashiers != null) {
        for (final c in cashiers.take(3)) {
          actions.add(SmartActionItem(
            id: 'cashier_${c.userId}',
            title: 'نشاط كاشير: ${c.name}',
            reason: c.flags.join(' • '),
            recommendation: 'راجع الجدول الزمني والمرتجعات',
            severity: SmartActionSeverity.warning,
            category: SmartActionCategory.cashier,
            priorityScore: 70,
            actionRoute: '/activity/timeline',
            entityType: 'user',
            entityId: c.userId,
          ));
        }
      }

      if (alerts != null) {
        for (final a in alerts.where((x) => x.isUnread).take(5)) {
          actions.add(SmartActionItem(
            id: 'alert_${a.fingerprint}',
            title: a.title,
            reason: a.reason,
            recommendation: 'راجع التنبيه التشغيلي',
            severity: a.severity == OperationalAlertSeverity.critical
                ? SmartActionSeverity.critical
                : SmartActionSeverity.warning,
            category: SmartActionCategory.workflow,
            priorityScore: a.priorityScore,
            actionRoute: a.actionRoute ?? '/operations/notifications',
          ));
        }
      }

      final wf = await _workflow.evaluate(alerts: alerts, cashiers: cashiers);
      for (final r in wf.results.take(3)) {
        actions.add(SmartActionItem(
          id: 'wf_${r.workflowId}',
          title: r.summaryAr,
          reason: r.reason ?? 'سير عمل مقترح',
          recommendation: r.actions.isNotEmpty ? r.actions.first.labelAr : 'مراجعة',
          severity: SmartActionSeverity.warning,
          category: SmartActionCategory.workflow,
          priorityScore: 75,
          actionRoute: r.actions.isNotEmpty ? r.actions.first.route : '/automation/actions',
        ));
      }

      actions.sort(SmartActionItem.compare);
      return _governance.governActions(actions);
    });
  }
}