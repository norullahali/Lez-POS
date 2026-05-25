import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../operations/services/operations_navigation.dart';
import '../models/automation_audit_context.dart';
import '../models/smart_action_item.dart';
import '../models/workflow_lifecycle_state.dart';

Color _severityColor(SmartActionSeverity s) => switch (s) {
      SmartActionSeverity.critical => AppColors.error,
      SmartActionSeverity.warning => AppColors.warning,
      SmartActionSeverity.info => AppColors.info,
    };

String _lifecycleLabel(WorkflowLifecycleState s) => switch (s) {
      WorkflowLifecycleState.pending => 'معلق',
      WorkflowLifecycleState.reviewed => 'تمت المراجعة',
      WorkflowLifecycleState.accepted => 'مقبول',
      WorkflowLifecycleState.ignored => 'متجاهل',
      WorkflowLifecycleState.expired => 'منتهي',
      WorkflowLifecycleState.completed => 'مكتمل',
    };

String _confidenceLabel(HeuristicConfidence c) => switch (c) {
      HeuristicConfidence.high => 'ثقة عالية',
      HeuristicConfidence.medium => 'ثقة متوسطة',
      HeuristicConfidence.low => 'ثقة منخفضة',
    };

class SmartActionCard extends StatelessWidget {
  const SmartActionCard({super.key, required this.action});
  final SmartActionItem action;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(action.severity);
    final audit = action.audit;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text('P${action.priorityScore}', style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
                const SizedBox(width: 6),
                Chip(
                  label: Text(_lifecycleLabel(action.lifecycleState), style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                ),
                if (action.occurrenceCount > 1) ...[
                  const SizedBox(width: 6),
                  Chip(
                    label: Text('x${action.occurrenceCount}', style: const TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    action.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('السبب: ${action.reason}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('التوصية: ${action.recommendation}', style: Theme.of(context).textTheme.bodyMedium),
            if (audit != null) ...[
              const SizedBox(height: 6),
              Text(
                'مصدر: ${audit.triggerSource} • ${_confidenceLabel(audit.confidence)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
              ),
            ],
            if (action.conflicts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'تعارض: ${action.conflicts.first.resolutionHintAr}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning),
              ),
            ],
            if (action.requiresApproval)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'يتطلب موافقة يدوية',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textHint),
                ),
              ),
            if (action.actionRoute != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => OperationsNavigation.navigate(context, action.actionRoute),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(action.actionLabel ?? 'عرض'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}