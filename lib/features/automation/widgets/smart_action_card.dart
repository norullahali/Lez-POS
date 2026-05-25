import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../operations/services/operations_navigation.dart';
import '../models/smart_action_item.dart';
import 'automation_ui_helpers.dart';
import 'operational_metric_chip.dart';

class SmartActionCard extends StatefulWidget {
  const SmartActionCard({super.key, required this.action});
  final SmartActionItem action;

  @override
  State<SmartActionCard> createState() => _SmartActionCardState();
}

class _SmartActionCardState extends State<SmartActionCard> {
  bool _hovered = false;

  SmartActionItem get action => widget.action;

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = AutomationUiHelpers.severityStyle(action.severity);
    final audit = action.audit;
    final metrics = AutomationUiHelpers.metricsForAction(action);
    final chips = <Widget>[
      OperationalMetricChip(
        label: style.label,
        icon: style.icon,
        color: style.color,
        background: style.background,
      ),
      OperationalMetricChip(
        label: AutomationUiHelpers.categoryLabel(action.category),
        icon: Icons.label_outline_rounded,
      ),
      if (audit != null)
        OperationalMetricChip(
          label: AutomationUiHelpers.confidenceShort(audit.confidence),
          icon: Icons.verified_outlined,
          color: AppColors.info,
          background: AppColors.infoLight,
        ),
      if (action.occurrenceCount > 1)
        OperationalMetricChip(
          label: 'متكرر x${action.occurrenceCount}',
          icon: Icons.repeat_rounded,
          color: AppColors.warning,
          background: AppColors.warningLight,
        ),
      if (action.severity == SmartActionSeverity.critical)
        const OperationalMetricChip(
          label: 'عاجل',
          icon: Icons.bolt_rounded,
          color: AppColors.error,
          background: AppColors.errorLight,
        ),
      if (action.conflicts.isNotEmpty)
        const OperationalMetricChip(
          label: 'يحتاج متابعة',
          icon: Icons.compare_arrows_rounded,
          color: AppColors.warning,
          background: AppColors.warningLight,
        ),
      if (AutomationUiHelpers.isFresh(action.lastRefreshedAt))
        const OperationalMetricChip(
          label: 'جديد',
          icon: Icons.fiber_new_rounded,
          color: AppColors.success,
          background: AppColors.successLight,
        ),
    ];

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: style.color,
                      borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(10)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  action.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                        fontSize: 13.5,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OperationalMetricChip(
                                label: 'P${action.priorityScore}',
                                color: style.color,
                                background: style.background,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: chips,
                          ),
                          if (metrics.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 2,
                              children: metrics
                                  .map(
                                    (m) => Text(
                                      '${m.label}: ${m.value}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                            fontSize: 10.5,
                                          ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            action.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                      height: 1.25,
                                      fontSize: 11.5,
                                    ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            action.recommendation,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                          ),
                          if (action.conflicts.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              action.conflicts.first.resolutionHintAr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.warning,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            _freshnessLine(),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textHint,
                                      fontSize: 10.5,
                                    ),
                          ),
                          const SizedBox(height: 6),
                          _footerActions(context),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _freshnessLine() {
    final parts = <String>[
      'الحالة: ${AutomationUiHelpers.lifecycleShort(action.lifecycleState)}',
      if (action.lastRefreshedAt != null)
        'آخر تحديث ${AutomationUiHelpers.relativeTimeAr(action.lastRefreshedAt)}',
      if (action.occurrenceCount > 1) 'تكرر ${action.occurrenceCount}×',
    ];
    return parts.join(' • ');
  }

  Widget _footerActions(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 0,
      children: [
        _actionBtn(
          label: action.actionLabel ?? 'عرض',
          icon: Icons.open_in_new_rounded,
          onPressed: action.actionRoute != null
              ? () => OperationsNavigation.navigate(context, action.actionRoute)
              : null,
        ),
        _actionBtn(
          label: 'إقرار',
          icon: Icons.check_circle_outline_rounded,
          onPressed: () =>
              _snack('الإقرار يتطلب موافقة يدوية — لا يتم تنفيذ إجراء تلقائي'),
        ),
        _actionBtn(
          label: 'حل',
          icon: Icons.task_alt_outlined,
          onPressed: () => _snack('تم تسجيل الحاجة للحل — راجع الإجراء يدوياً'),
        ),
        _actionBtn(
          label: 'أرشفة',
          icon: Icons.archive_outlined,
          onPressed: () => _snack('الأرشفة متاحة بعد المراجعة اليدوية'),
        ),
      ],
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label),
    );
  }
}
