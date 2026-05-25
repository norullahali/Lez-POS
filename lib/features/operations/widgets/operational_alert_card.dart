import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_state.dart';
import '../models/operational_alert_type.dart';
import '../services/operations_navigation.dart';
import 'notification_bell.dart';

class OperationalAlertCard extends StatelessWidget {
  const OperationalAlertCard({
    super.key,
    required this.alert,
    required this.onDismiss,
    this.onAcknowledge,
    this.onResolve,
  });

  final OperationalAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback? onAcknowledge;
  final VoidCallback? onResolve;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(alert.severity);
    final inactive = !alert.state.isVisibleInInbox;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: inactive ? AppColors.border : color.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    severityLabel(alert.severity),
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 6),
                Chip(
                  label: Text(alert.state.labelAr, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                if (alert.isGrouped) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: Text('${alert.groupedCount}', style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                const Spacer(),
                Text(
                  'P${alert.priorityScore}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              alert.type.labelAr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
            ),
            const SizedBox(height: 8),
            Text(
              alert.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(alert.description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              'السبب: ${alert.reason}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            if (alert.occurrenceCount > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'تكرار: ${alert.occurrenceCount}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (alert.actionRoute != null)
                  TextButton.icon(
                    onPressed: () => OperationsNavigation.navigate(context, alert.actionRoute),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: Text(alert.actionLabel ?? 'عرض'),
                  ),
                if (alert.state == OperationalAlertState.active && onAcknowledge != null)
                  TextButton(
                    onPressed: onAcknowledge,
                    child: const Text('إقرار'),
                  ),
                if (onResolve != null &&
                    alert.state != OperationalAlertState.resolved &&
                    alert.state != OperationalAlertState.archived)
                  TextButton(
                    onPressed: onResolve,
                    child: const Text('حل'),
                  ),
                if (alert.state.isVisibleInInbox)
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('أرشفة'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}