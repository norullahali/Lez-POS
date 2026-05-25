import '../cache/automation_cache.dart';
import 'business_assistant_service.dart';
import 'customer_loyalty_engine.dart';
import 'debt_follow_up_service.dart';
import 'reorder_suggestion_service.dart';
import 'smart_action_center_service.dart';
import '../../operations/services/daily_snapshot_service.dart';
import '../../operations/services/operational_alert_service.dart';
import '../../operations/services/operational_evaluation_cache.dart';

class AutomationDailyTasksService {
  AutomationDailyTasksService({
    required OperationalAlertService alertService,
    required DailySnapshotService? snapshotService,
    required ReorderSuggestionService reorder,
    required DebtFollowUpService debt,
    required CustomerLoyaltyEngine loyalty,
    required SmartActionCenterService actionCenter,
    required BusinessAssistantService assistant,
  })  : _alertService = alertService,
        _snapshotService = snapshotService,
        _reorder = reorder,
        _debt = debt,
        _loyalty = loyalty,
        _actionCenter = actionCenter,
        _assistant = assistant;

  final OperationalAlertService _alertService;
  final DailySnapshotService? _snapshotService;
  final ReorderSuggestionService _reorder;
  final DebtFollowUpService _debt;
  final CustomerLoyaltyEngine _loyalty;
  final SmartActionCenterService _actionCenter;
  final BusinessAssistantService _assistant;

  Future<void> runDailyRefresh() async {
    AutomationCache.invalidatePrefix('');
    OperationalEvaluationCache.clear();
    await _alertService.refresh();
    final alerts = await _alertService.loadAlerts(useCache: true);
    await _snapshotService?.captureTodayIfNeeded(alerts: alerts);
    await Future.wait([
      _reorder.generate(),
      _debt.generate(),
      _loyalty.generateInsights(),
      _assistant.buildGuidance(),
      _actionCenter.buildActions(alerts: alerts),
    ]);
  }

  Future<void> runWeeklyRefresh() async {
    await runDailyRefresh();
  }
}