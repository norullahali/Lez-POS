import 'package:flutter/material.dart';
import '../../../core/activity/activity_categories.dart';
import '../../../core/theme/app_colors.dart';

class ActivityCategoryChip extends StatelessWidget {
  const ActivityCategoryChip({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ActivityCategories.iconFor(category),
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            ActivityCategories.labelAr(category),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}