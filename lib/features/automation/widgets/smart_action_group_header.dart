import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../governance/smart_action_grouping_service.dart';
import '../models/smart_action_group.dart';
import '../models/smart_action_item.dart';
import 'automation_ui_helpers.dart';
import 'operational_metric_chip.dart';
import 'smart_action_card.dart';

class SmartActionGroupHeader extends StatelessWidget {
  const SmartActionGroupHeader({
    super.key,
    required this.section,
    required this.collapsed,
    required this.onToggle,
  });

  final SmartActionGroupedSection section;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final critical = section.items.where((i) => i.severity == SmartActionSeverity.critical).length;
    final warning = section.items.where((i) => i.severity == SmartActionSeverity.warning).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Material(
        color: AppColors.surfaceVariant.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(
                  AutomationUiHelpers.groupIcon(section.group),
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.group.labelAr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                  ),
                ),
                OperationalMetricChip(label: '${section.items.length}'),
                if (critical > 0) ...[
                  const SizedBox(width: 4),
                  OperationalMetricChip(
                    label: '$critical حرج',
                    color: AppColors.error,
                    background: AppColors.errorLight,
                    icon: Icons.priority_high_rounded,
                  ),
                ],
                if (warning > 0) ...[
                  const SizedBox(width: 4),
                  OperationalMetricChip(
                    label: '$warning مرتفع',
                    color: AppColors.warning,
                    background: AppColors.warningLight,
                  ),
                ],
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: collapsed ? 0 : 0.5,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SmartActionSectionBlock extends StatelessWidget {
  const SmartActionSectionBlock({
    super.key,
    required this.section,
    required this.collapsed,
    required this.onToggle,
  });

  final SmartActionGroupedSection section;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SmartActionGroupHeader(
          section: section,
          collapsed: collapsed,
          onToggle: onToggle,
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: collapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeIn,
          sizeCurve: Curves.easeOut,
          firstChild: Column(
            children: [
              for (final item in section.items) SmartActionCard(action: item),
              const SizedBox(height: 4),
            ],
          ),
          secondChild: const SizedBox(height: 2),
        ),
      ],
    );
  }
}
