import 'package:flutter/material.dart';
import '../../../core/activity/activity_severity.dart';

class ActivitySeverityChip extends StatelessWidget {
  const ActivitySeverityChip({
    super.key,
    required this.severity,
    this.showIcon = false,
  });

  final String severity;
  final bool showIcon;

  IconData? get _icon => switch (severity) {
        ActivitySeverity.warning => Icons.warning_amber_rounded,
        ActivitySeverity.critical => Icons.error_outline_rounded,
        ActivitySeverity.security => Icons.security_rounded,
        _ => Icons.info_outline_rounded,
      };

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(_icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            ActivitySeverity.labelAr(severity),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}