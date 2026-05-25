import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class OperationalMetricChip extends StatelessWidget {
  const OperationalMetricChip({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.background,
    this.dense = true,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.textSecondary;
    final bg = background ?? AppColors.surfaceVariant;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(fontSize: dense ? 10.5 : 11, fontWeight: FontWeight.w600, color: fg, height: 1.1),
          ),
        ],
      ),
    );
  }
}