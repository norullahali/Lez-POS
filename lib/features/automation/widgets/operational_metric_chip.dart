import 'package:flutter/material.dart';

class OperationalMetricChip extends StatelessWidget {
  const OperationalMetricChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    Color? backgroundColor,
    Color? background,
  }) : backgroundColor = backgroundColor ?? background;

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.onSurfaceVariant;
    final backgroundFill =
        backgroundColor ?? theme.colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundFill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: foreground,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
