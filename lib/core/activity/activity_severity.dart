// lib/core/activity/activity_severity.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ActivitySeverity {
  ActivitySeverity._();

  static const info = 'info';
  static const warning = 'warning';
  static const critical = 'critical';
  static const security = 'security';

  static const all = [info, warning, critical, security];

  static String labelAr(String severity) => switch (severity) {
        info => 'معلومات',
        warning => 'تحذير',
        critical => 'حرج',
        security => 'أمني',
        _ => severity,
      };

  static Color color(String severity) => switch (severity) {
        warning => AppColors.warning,
        critical => AppColors.error,
        security => AppColors.primaryDark,
        _ => AppColors.info,
      };
}