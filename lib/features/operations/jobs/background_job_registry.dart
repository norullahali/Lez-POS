import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/operations_thresholds.dart';
import '../models/background_job.dart';
import '../models/background_job_execution_result.dart';
import '../models/scheduled_report_config.dart';
import '../services/daily_snapshot_service.dart';
import '../services/operational_alert_service.dart';
import '../services/operational_evaluation_cache.dart';
import '../services/scheduled_reports_service.dart';

class BackgroundJobRegistry {
  BackgroundJobRegistry({
    required OperationalAlertService alertService,
    required ScheduledReportsService scheduledReports,
    DailySnapshotService? snapshotService,
  })  : _alertService = alertService,
        _scheduledReports = scheduledReports,
        _snapshotService = snapshotService;

  final OperationalAlertService _alertService;
  final ScheduledReportsService _scheduledReports;
  final DailySnapshotService? _snapshotService;

  List<BackgroundJob> buildJobs() => [
        BackgroundJob(
          id: 'refresh_alerts',
          labelAr: 'تحديث التنبيهات التشغيلية',
          runOnStartup: true,
          handler: () async {
            await _alertService.refresh();
          },
        ),
        BackgroundJob(
          id: 'generate_scheduled_reports',
          labelAr: 'توليد التقارير المجدولة',
          runOnStartup: true,
          handler: () async {
            final configs = await _scheduledReports.loadConfigs();
            final updated = <ScheduledReportConfig>[];
            for (final c in configs) {
              final result = await _scheduledReports.generateIfDue(c);
              updated.add(result ?? c);
            }
            await _scheduledReports.saveConfigs(updated);
          },
        ),
        BackgroundJob(
          id: 'capture_daily_snapshot',
          labelAr: 'حفظ لقطة تشغيلية يومية',
          runOnStartup: true,
          handler: () async {
            final alerts = await _alertService.loadAlerts(useCache: true);
            await _snapshotService?.captureTodayIfNeeded(alerts: alerts);
          },
        ),
        BackgroundJob(
          id: 'cleanup_cache',
          labelAr: 'تنظيف ذاكرة التحليلات',
          handler: () async {
            OperationalEvaluationCache.clear();
          },
        ),
      ];
}

class BackgroundJobRunner {
  BackgroundJobRunner(this._jobs);

  final List<BackgroundJob> _jobs;
  bool _started = false;
  final Set<String> _running = {};
  final Map<String, BackgroundJobExecutionResult> _lastResults = {};

  Map<String, BackgroundJobExecutionResult> get lastResults =>
      Map.unmodifiable(_lastResults);

  Future<void> initializeOnStartup() async {
    if (_started) return;
    _started = true;

    await Future<void>.delayed(
      Duration(seconds: OperationsThresholds.jobStartupDelaySeconds),
    );
    for (final job in _jobs.where((j) => j.runOnStartup)) {
      await runJob(job.id);
    }
  }

  Future<BackgroundJobExecutionResult?> runJob(String id) async {
    final job = _jobs.where((j) => j.id == id).firstOrNull;
    if (job == null) return null;

    if (_running.contains(id)) {
      final skipped = BackgroundJobExecutionResult(
        jobId: id,
        status: BackgroundJobStatus.skipped,
        startedAt: DateTime.now(),
        completedAt: DateTime.now(),
        errorMessage: 'Job already running',
      );
      _lastResults[id] = skipped;
      return skipped;
    }

    _running.add(id);
    final startedAt = DateTime.now();
    _lastResults[id] = BackgroundJobExecutionResult(
      jobId: id,
      status: BackgroundJobStatus.running,
      startedAt: startedAt,
    );

    var attempt = 0;
    while (attempt <= OperationsThresholds.jobMaxRetries) {
      attempt++;
      try {
        debugPrint('[BackgroundJob] $id attempt $attempt started');
        await job.handler();
        final result = BackgroundJobExecutionResult(
          jobId: id,
          status: BackgroundJobStatus.completed,
          startedAt: startedAt,
          completedAt: DateTime.now(),
          attempt: attempt,
        );
        _lastResults[id] = result;
        _running.remove(id);
        debugPrint('[BackgroundJob] $id completed');
        return result;
      } catch (e, st) {
        debugPrint('[BackgroundJob] $id failed: $e\n$st');
        if (attempt > OperationsThresholds.jobMaxRetries) {
          final result = BackgroundJobExecutionResult(
            jobId: id,
            status: BackgroundJobStatus.failed,
            startedAt: startedAt,
            completedAt: DateTime.now(),
            errorMessage: e.toString(),
            attempt: attempt,
          );
          _lastResults[id] = result;
          _running.remove(id);
          return result;
        }
      }
    }

    _running.remove(id);
    return _lastResults[id];
  }
}