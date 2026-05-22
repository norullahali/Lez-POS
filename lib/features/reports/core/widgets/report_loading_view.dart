import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ReportLoadingView extends StatelessWidget {
  const ReportLoadingView({super.key, this.message = 'جاري تحميل التقرير...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}