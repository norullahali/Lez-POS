import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../operations/models/background_job.dart';
import '../../operations/models/background_job_execution_result.dart';
import '../models/automation_scheduler_status.dart';
import '../stores/automation_scheduler_status_store.dart';
import '../services/automation_daily_tasks_service.dart';
import '../services/debt_follow_up_service.dart';
import '../services/customer_loyalty_engine.dart';
import '../services/reorder_suggestion_service.dart';

class AutomationJobRegistry {
  AutomationJobRegistry({
    required AutomationDailyTasksService dailyTasks,
    required ReorderSuggestionService reorder,
    required DebtFollowUpService debt,
    required CustomerLoyaltyEngine loyalty,
  })  : _dailyTasks = dailyTasks,
        _reorder = reorder,
        _debt = debt,
        _loyalty = loyalty;

  final AutomationDailyTasksService _dailyTasks;
  final ReorderSuggestionService _reorder;
  final DebtFollowUpService _debt;
  final CustomerLoyaltyEngine _loyalty;

  List<BackgroundJob> buildJobs() => [
        BackgroundJob(
          id: 'automation_startup',
          labelAr: 'تهيئة الأتمتة',
          runOnStartup: true,
          handler: () => _dailyTasks.runDailyRefresh(),
        ),
        BackgroundJob(
          id: 'automation_daily_refresh',
          labelAr: 'تحديث يومي',
          runOnStartup: false,
          handler: () => _dailyTasks.runDailyRefresh(),
        ),
        BackgroundJob(
          id: 'automation_weekly_review',
          labelAr: 'مراجعة أسبوعية',
          handler: () => _dailyTasks.runWeeklyRefresh(),
        ),
        BackgroundJob(
          id: 'automation_reorder',
          labelAr: 'اقتراحات إعادة الطلب',
          handler: () => _reorder.generate(),
        ),
        BackgroundJob(
          id: 'automation_debt',
          labelAr: 'تحليل الذمم',
          handler: () => _debt.generate(),
        ),
        BackgroundJob(
          id: 'automation_loyalty',
          labelAr: 'تحديث الولاء',
          handler: () => _loyalty.generateInsights(),
        ),
      ];
}

class AutomationJobRunner {
  AutomationJobRunner(this._jobs);

  final List<BackgroundJob> _jobs;
  bool _started = false;
  final Set<String> _running = {};

  Future<AutomationSchedulerStatus> status() => AutomationSchedulerStatusStore.load();

  Future<void> initializeOnStartup() async {
    if (_started) return;
    _started = true;
    await Future<void>.delayed(const Duration(seconds: 3));
    for (final job in _jobs.where((j) => j.runOnStartup)) {
      await runJob(job.id);
    }
  }

  Future<BackgroundJobExecutionResult?> runJob(String id) async {
    if (_running.contains(id)) {
      final now = DateTime.now();
      await AutomationSchedulerStatusStore.record(
        AutomationJobRunRecord(
          jobId: id,
          outcome: AutomationJobRunOutcome.skipped,
          startedAt: now,
          completedAt: now,
          skippedReason: 'Already running',
        ),
      );
      return BackgroundJobExecutionResult(
        jobId: id,
        status: BackgroundJobStatus.skipped,
        startedAt: now,
        completedAt: now,
        errorMessage: 'Already running',
      );
    }
    _running.add(id);
    final started = DateTime.now();
    final sw = Stopwatch()..start();
    try {
      final job = _jobs.firstWhere((j) => j.id == id);
      debugPrint('[AutomationJob] $id started');
      await job.handler();
      sw.stop();
      debugPrint('[AutomationJob] $id completed');
      await AutomationSchedulerStatusStore.record(
        AutomationJobRunRecord(
          jobId: id,
          outcome: AutomationJobRunOutcome.success,
          startedAt: started,
          completedAt: DateTime.now(),
          durationMs: sw.elapsedMilliseconds,
        ),
      );
      return BackgroundJobExecutionResult(
        jobId: id,
        status: BackgroundJobStatus.completed,
        startedAt: started,
        completedAt: DateTime.now(),
      );
    } catch (e, st) {
      sw.stop();
      debugPrint('[AutomationJob] $id failed: $e\n$st');
      final current = await AutomationSchedulerStatusStore.load();
      final prev = current.jobs[id];
      await AutomationSchedulerStatusStore.record(
        AutomationJobRunRecord(
          jobId: id,
          outcome: AutomationJobRunOutcome.failed,
          startedAt: started,
          completedAt: DateTime.now(),
          durationMs: sw.elapsedMilliseconds,
          errorMessage: e.toString(),
          retryCount: (prev?.retryCount ?? 0) + 1,
        ),
      );
      return BackgroundJobExecutionResult(
        jobId: id,
        status: BackgroundJobStatus.failed,
        startedAt: started,
        completedAt: DateTime.now(),
        errorMessage: e.toString(),
      );
    } finally {
      _running.remove(id);
    }
  }
}
