import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../models/store_operational_health.dart';
import '../providers/operations_providers.dart';

class OperationalHealthCard extends ConsumerWidget {
  const OperationalHealthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(storeOperationalHealthProvider);

    return healthAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (health) {
        final color = switch (health.status) {
          StoreHealthStatus.excellent => AppColors.success,
          StoreHealthStatus.healthy => AppColors.info,
          StoreHealthStatus.warning => AppColors.warning,
          StoreHealthStatus.critical => AppColors.error,
        };

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'الصحة التشغيلية',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${health.score}/100',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Chip(
                  label: Text(health.status.labelAr),
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 8),
                ...health.factors.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(f, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}