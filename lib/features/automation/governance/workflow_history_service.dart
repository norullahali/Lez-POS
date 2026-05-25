import '../../../core/activity/activity_categories.dart';
import '../../../core/services/activity_logger_service.dart';
import '../models/workflow_lifecycle_state.dart';
import '../stores/workflow_lifecycle_store.dart';

class WorkflowHistoryService {
  WorkflowHistoryService(this._logger);
  final ActivityLoggerService? _logger;

  Future<WorkflowLifecycleRecord> recordGeneration({
    required String workflowId,
    required String fingerprint,
    required String whyGenerated,
    required String sourceEngine,
    required String triggerSource,
  }) async {
    final record = await WorkflowLifecycleStore.touch(
      workflowId: workflowId,
      fingerprint: fingerprint,
      whyGenerated: whyGenerated,
      sourceEngine: sourceEngine,
      triggerSource: triggerSource,
    );
    await _logger?.logInfo(
      activityType: 'automation.workflow.generated',
      category: ActivityCategories.settings,
      action: 'generate',
      title: 'سير عمل مقترح: $workflowId',
      description: whyGenerated,
      metadata: {
        'fingerprint': fingerprint,
        'sourceEngine': sourceEngine,
        'triggerSource': triggerSource,
      },
    );
    return record;
  }

  Future<WorkflowLifecycleRecord?> transition(
    String fingerprint,
    WorkflowLifecycleState next, {
    String? note,
  }) async {
    final updated = await WorkflowLifecycleStore.transition(fingerprint, next);
    if (updated == null || _logger == null) return updated;
    await _logger!.logInfo(
      activityType: 'automation.workflow.${next.name}',
      category: ActivityCategories.settings,
      action: next.name,
      title: 'تحديث سير عمل',
      description: note ?? updated.whyGenerated,
      metadata: {
        'fingerprint': fingerprint,
        'workflowId': updated.workflowId,
        'state': next.name,
      },
    );
    return updated;
  }
}