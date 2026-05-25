import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_scheduler_status.dart';

class AutomationSchedulerStatusStore {
  AutomationSchedulerStatusStore._();
  static const _key = 'automation_scheduler_status_v1';

  static Future<AutomationSchedulerStatus> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return const AutomationSchedulerStatus(jobs: {});
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final jobs = <String, AutomationJobRunRecord>{};
      DateTime? updatedAt;
      for (final entry in map.entries) {
        if (entry.key == '_updated') {
          updatedAt = DateTime.tryParse(entry.value as String);
          continue;
        }
        final j = entry.value as Map<String, dynamic>;
        jobs[entry.key] = AutomationJobRunRecord(
          jobId: j['jobId'] as String,
          outcome: AutomationJobRunOutcome.values.firstWhere(
            (e) => e.name == j['outcome'],
            orElse: () => AutomationJobRunOutcome.success,
          ),
          startedAt: DateTime.parse(j['startedAt'] as String),
          completedAt: j['completedAt'] != null ? DateTime.tryParse(j['completedAt'] as String) : null,
          durationMs: j['durationMs'] as int?,
          skippedReason: j['skippedReason'] as String?,
          errorMessage: j['errorMessage'] as String?,
          retryCount: (j['retryCount'] as int?) ?? 0,
        );
      }
      return AutomationSchedulerStatus(
        jobs: jobs,
        lastUpdatedAt: updatedAt,
      );
    } catch (_) {
      return const AutomationSchedulerStatus(jobs: {});
    }
  }

  static Future<void> record(AutomationJobRunRecord record) async {
    final current = await load();
    final jobs = Map<String, AutomationJobRunRecord>.from(current.jobs);
    final prev = jobs[record.jobId];
    final merged = AutomationJobRunRecord(
      jobId: record.jobId,
      outcome: record.outcome,
      startedAt: record.startedAt,
      completedAt: record.completedAt,
      durationMs: record.durationMs,
      skippedReason: record.skippedReason,
      errorMessage: record.errorMessage,
      retryCount: record.outcome == AutomationJobRunOutcome.failed
          ? (prev?.retryCount ?? 0) + 1
          : record.retryCount,
    );
    jobs[record.jobId] = merged;
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      for (final entry in jobs.entries)
        entry.key: {
          'jobId': entry.value.jobId,
          'outcome': entry.value.outcome.name,
          'startedAt': entry.value.startedAt.toIso8601String(),
          'completedAt': entry.value.completedAt?.toIso8601String(),
          'durationMs': entry.value.durationMs,
          'skippedReason': entry.value.skippedReason,
          'errorMessage': entry.value.errorMessage,
          'retryCount': entry.value.retryCount,
        },
      '_updated': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_key, jsonEncode(payload));
  }
}