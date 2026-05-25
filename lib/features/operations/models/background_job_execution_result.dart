enum BackgroundJobStatus {
  idle,
  running,
  completed,
  failed,
  skipped,
}

class BackgroundJobExecutionResult {
  const BackgroundJobExecutionResult({
    required this.jobId,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
    this.attempt = 1,
  });

  final String jobId;
  final BackgroundJobStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? errorMessage;
  final int attempt;

  bool get succeeded => status == BackgroundJobStatus.completed;
}
