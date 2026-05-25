import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/permissions/permission_keys.dart';
import '../../auth/providers/permission_provider.dart';
import '../../operations/providers/operations_providers.dart';
import '../governance/recommendation_governance_service.dart';
import '../governance/smart_action_grouping_service.dart';
import '../governance/workflow_history_service.dart';
import '../models/automation_scheduler_status.dart';
import '../../activity/providers/activity_context_provider.dart';
import '../models/business_guidance_item.dart';
import '../models/debt_follow_up_item.dart';
import '../models/loyalty_insight.dart';
import '../models/purchase_recommendation.dart';
import '../models/reorder_suggestion.dart';
import '../models/restock_plan_item.dart';
import '../models/smart_action_item.dart';
import '../models/workflow_execution_result.dart';
import '../repositories/automation_repository.dart';
import '../scheduler/automation_job_registry.dart';
import '../services/automation_daily_tasks_service.dart';
import '../services/business_assistant_service.dart';
import '../services/customer_loyalty_engine.dart';
import '../services/debt_follow_up_service.dart';
import '../services/purchase_recommendation_service.dart';
import '../services/reorder_suggestion_service.dart';
import '../services/restock_planning_service.dart';
import '../services/smart_action_center_service.dart';
import '../workflows/workflow_engine_service.dart';

final automationRepositoryProvider = Provider<AutomationRepository>((ref) {
  return AutomationRepository(AppDatabase.instance);
});

final workflowHistoryServiceProvider = Provider<WorkflowHistoryService>((ref) {
  return WorkflowHistoryService(ref.watch(activityLoggerProvider));
});

final recommendationGovernanceServiceProvider = Provider<RecommendationGovernanceService>((ref) {
  return RecommendationGovernanceService(history: ref.watch(workflowHistoryServiceProvider));
});

final reorderSuggestionServiceProvider = Provider<ReorderSuggestionService>((ref) {
  return ReorderSuggestionService(ref.watch(automationRepositoryProvider));
});

final purchaseRecommendationServiceProvider = Provider<PurchaseRecommendationService>((ref) {
  return PurchaseRecommendationService(ref.watch(reorderSuggestionServiceProvider));
});

final restockPlanningServiceProvider = Provider<RestockPlanningService>((ref) {
  return RestockPlanningService(
    ref.watch(automationRepositoryProvider),
    ref.watch(reorderSuggestionServiceProvider),
  );
});

final debtFollowUpServiceProvider = Provider<DebtFollowUpService>((ref) {
  return DebtFollowUpService(ref.watch(automationRepositoryProvider));
});

final customerLoyaltyEngineProvider = Provider<CustomerLoyaltyEngine>((ref) {
  return CustomerLoyaltyEngine(ref.watch(automationRepositoryProvider));
});

final workflowEngineServiceProvider = Provider<WorkflowEngineService>((ref) {
  return WorkflowEngineService(
    reorder: ref.watch(reorderSuggestionServiceProvider),
    debt: ref.watch(debtFollowUpServiceProvider),
    governance: ref.watch(recommendationGovernanceServiceProvider),
  );
});

final smartActionCenterServiceProvider = Provider<SmartActionCenterService>((ref) {
  return SmartActionCenterService(
    reorder: ref.watch(reorderSuggestionServiceProvider),
    purchase: ref.watch(purchaseRecommendationServiceProvider),
    restock: ref.watch(restockPlanningServiceProvider),
    debt: ref.watch(debtFollowUpServiceProvider),
    loyalty: ref.watch(customerLoyaltyEngineProvider),
    workflow: ref.watch(workflowEngineServiceProvider),
    governance: ref.watch(recommendationGovernanceServiceProvider),
  );
});

final businessAssistantServiceProvider = Provider<BusinessAssistantService>((ref) {
  return BusinessAssistantService(
    ref.watch(automationRepositoryProvider),
    ref.watch(operationsRepositoryProvider),
    governance: ref.watch(recommendationGovernanceServiceProvider),
  );
});

final automationDailyTasksServiceProvider = Provider<AutomationDailyTasksService>((ref) {
  return AutomationDailyTasksService(
    alertService: ref.watch(operationalAlertServiceProvider),
    snapshotService: ref.watch(dailySnapshotServiceProvider),
    reorder: ref.watch(reorderSuggestionServiceProvider),
    debt: ref.watch(debtFollowUpServiceProvider),
    loyalty: ref.watch(customerLoyaltyEngineProvider),
    actionCenter: ref.watch(smartActionCenterServiceProvider),
    assistant: ref.watch(businessAssistantServiceProvider),
  );
});

final automationJobRegistryProvider = Provider<AutomationJobRegistry>((ref) {
  return AutomationJobRegistry(
    dailyTasks: ref.watch(automationDailyTasksServiceProvider),
    reorder: ref.watch(reorderSuggestionServiceProvider),
    debt: ref.watch(debtFollowUpServiceProvider),
    loyalty: ref.watch(customerLoyaltyEngineProvider),
  );
});

final automationJobRunnerProvider = Provider<AutomationJobRunner>((ref) {
  return AutomationJobRunner(
    ref.watch(automationJobRegistryProvider).buildJobs(),
  );
});

final canViewAutomationProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.automationView));
});

final canManageAutomationProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.automationManage));
});

final smartActionsGroupedProvider = FutureProvider<List<SmartActionGroupedSection>>((ref) async {
  final actions = await ref.watch(smartActionsProvider.future);
  return SmartActionGroupingService.group(actions);
});

final automationSchedulerStatusProvider = FutureProvider<AutomationSchedulerStatus>((ref) async {
  return ref.watch(automationJobRunnerProvider).status();
});

final smartActionsProvider = FutureProvider<List<SmartActionItem>>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) return [];
  final alerts = ref.watch(operationalAlertsProvider).valueOrNull;
  final cashiers = ref.watch(cashierBehaviorProvider).valueOrNull;
  return ref.watch(smartActionCenterServiceProvider).buildActions(
        alerts: alerts,
        cashiers: cashiers,
      );
});

final reorderSuggestionsProvider = FutureProvider<List<ReorderSuggestion>>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) return [];
  return ref.watch(reorderSuggestionServiceProvider).generate();
});

final purchaseRecommendationsProvider = FutureProvider<List<SupplierPurchaseRecommendation>>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) return [];
  return ref.watch(purchaseRecommendationServiceProvider).generate();
});

final restockPlanProvider = FutureProvider<List<RestockPlanItem>>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) return [];
  return ref.watch(restockPlanningServiceProvider).buildPlan();
});

final debtFollowUpProvider = FutureProvider<List<DebtFollowUpItem>>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) return [];
  return ref.watch(debtFollowUpServiceProvider).generate();
});

final loyaltyInsightsProvider = FutureProvider<List<LoyaltyInsight>>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) return [];
  return ref.watch(customerLoyaltyEngineProvider).generateInsights();
});

final businessGuidanceProvider = FutureProvider<List<BusinessGuidanceItem>>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) return [];
  return ref.watch(businessAssistantServiceProvider).buildGuidance();
});

final workflowEvaluationProvider = FutureProvider<WorkflowEvaluationBundle>((ref) async {
  if (!ref.watch(canViewAutomationProvider)) {
    return const WorkflowEvaluationBundle(results: [], definitions: []);
  }
  return ref.watch(workflowEngineServiceProvider).evaluate(
        alerts: ref.watch(operationalAlertsProvider).valueOrNull,
        cashiers: ref.watch(cashierBehaviorProvider).valueOrNull,
      );
});

final automationStartupProvider = Provider<void>((ref) {
  Future.microtask(() {
    ref.read(automationJobRunnerProvider).initializeOnStartup();
  });
});