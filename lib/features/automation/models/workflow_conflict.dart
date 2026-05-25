enum WorkflowConflictSeverity { info, warning, critical }

class WorkflowConflict {
  const WorkflowConflict({
    required this.id,
    required this.titleAr,
    required this.descriptionAr,
    required this.resolutionHintAr,
    required this.severity,
    required this.fingerprintA,
    required this.fingerprintB,
  });

  final String id;
  final String titleAr;
  final String descriptionAr;
  final String resolutionHintAr;
  final WorkflowConflictSeverity severity;
  final String fingerprintA;
  final String fingerprintB;
}