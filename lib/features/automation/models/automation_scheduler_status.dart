enum AutomationJobRunOutcome { success, failed, skipped }

class AutomationJobRunRecord {
  const AutomationJobRunRecord({
    required this.jobId,
    required this.outcome,
    required this.startedAt,
    this.completedAt,
    this.durationMs,
    this.skippedReason,
    this.errorMessage,
    this.retryCount = 0,
  });

  final String jobId;
  final AutomationJobRunOutcome outcome;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int? durationMs;
  final String? skippedReason;
  final String? errorMessage;
  final int retryCount;
}

class AutomationSchedulerStatus {
  const AutomationSchedulerStatus({
    required this.jobs,
    this.lastUpdatedAt,
  });

  final Map<String, AutomationJobRunRecord> jobs;
  final DateTime? lastUpdatedAt;

  AutomationJobRunRecord? lastSuccess(String jobId) {
    final r = jobs[jobId];
    return r?.outcome == AutomationJobRunOutcome.success ? r : null;
  }

  AutomationJobRunRecord? lastFailed(String jobId) {
    final r = jobs[jobId];
    return r?.outcome == AutomationJobRunOutcome.failed ? r : null;
  }
}