import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../models/operational_alert_severity.dart';
import '../providers/operations_providers.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canViewAlertsProvider)) {
      return const SizedBox.shrink();
    }

    final unread = ref.watch(operationalUnreadCountProvider);

    return IconButton(
      tooltip: 'مركز الإشعارات',
      onPressed: () => context.go('/operations/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.notifications_outlined, color: AppColors.textPrimary),
      ),
    );
  }
}

Color severityColor(OperationalAlertSeverity severity) {
  return switch (severity) {
    OperationalAlertSeverity.critical => AppColors.error,
    OperationalAlertSeverity.warning => AppColors.warning,
    OperationalAlertSeverity.info => AppColors.info,
  };
}

String severityLabel(OperationalAlertSeverity severity) {
  return switch (severity) {
    OperationalAlertSeverity.critical => 'حرج',
    OperationalAlertSeverity.warning => 'تحذير',
    OperationalAlertSeverity.info => 'معلومة',
  };
}
