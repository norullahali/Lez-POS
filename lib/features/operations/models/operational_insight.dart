import 'operational_alert_severity.dart';

class OperationalInsight {
  const OperationalInsight({
    required this.id,
    required this.message,
    required this.severity,
    required this.createdAt,
    this.category,
    this.actionRoute,
    this.priorityScore = 0,
    this.urgencyScore = 0,
  });

  final String id;
  final String message;
  final OperationalAlertSeverity severity;
  final DateTime createdAt;
  final String? category;
  final String? actionRoute;
  final int priorityScore;
  final int urgencyScore;

  static int compare(OperationalInsight a, OperationalInsight b) {
    final p = b.priorityScore.compareTo(a.priorityScore);
    if (p != 0) return p;
    final u = b.urgencyScore.compareTo(a.urgencyScore);
    if (u != 0) return u;
    final s = a.severity.sortOrder.compareTo(b.severity.sortOrder);
    if (s != 0) return s;
    return b.createdAt.compareTo(a.createdAt);
  }
}