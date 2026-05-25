import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../models/expiry_alert.dart';
import '../providers/operations_providers.dart';

class ExpiryDashboardCard extends ConsumerWidget {
  const ExpiryDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapAsync = ref.watch(expiryMonitoringProvider);

    return snapAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (snap) {
        if (!snap.trackingEnabled) {
          return Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.event_busy, color: AppColors.textHint.withValues(alpha: 0.7)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'تتبع الصلاحية غير مفعّل — لا توجد دفعات أو منتجات بصلاحية',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textHint),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final expired = snap.items.where((i) => i.level == ExpiryAlertLevel.expired).length;
        final critical = snap.items.where((i) => i.level == ExpiryAlertLevel.critical).length;
        final warning = snap.items.where((i) => i.level == ExpiryAlertLevel.warning).length;

        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مراقبة الصلاحية',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _chip('منتهي', expired, AppColors.error),
                    _chip('حرج', critical, AppColors.warning),
                    _chip('قريب', warning, AppColors.info),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text('$count', style: TextStyle(color: color, fontSize: 12)),
      ),
      label: Text(label),
    );
  }
}
