import 'package:flutter/material.dart';
import '../../../core/activity/activity_categories.dart';
import '../../../core/theme/app_colors.dart';

class ActivityCategoryIcon extends StatelessWidget {
  const ActivityCategoryIcon({
    super.key,
    required this.category,
    this.size = 18,
    this.color,
  });

  final String category;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Icon(
      ActivityCategories.iconFor(category),
      size: size,
      color: color ?? AppColors.textSecondary,
    );
  }
}