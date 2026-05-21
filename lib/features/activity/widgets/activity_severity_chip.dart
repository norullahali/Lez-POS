import 'package:flutter/material.dart';
import '../../../core/activity/activity_severity.dart';

class ActivitySeverityChip extends StatelessWidget {
  const ActivitySeverityChip({super.key, required this.severity});
  final String severity;

  @override
  Widget build(BuildContext context) {
    final color = ActivitySeverity.color(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        ActivitySeverity.labelAr(severity),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}