import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../operations/services/operations_navigation.dart';
import '../models/business_guidance_item.dart';
import 'automation_ui_helpers.dart';
import 'operational_metric_chip.dart';

class BusinessGuidanceTile extends StatefulWidget {
  const BusinessGuidanceTile({super.key, required this.item});
  final BusinessGuidanceItem item;

  @override
  State<BusinessGuidanceTile> createState() => _BusinessGuidanceTileState();
}

class _BusinessGuidanceTileState extends State<BusinessGuidanceTile> {
  bool _hovered = false;

  BusinessGuidanceItem get item => widget.item;

  @override
  Widget build(BuildContext context) {
    final style = AutomationUiHelpers.guidanceStyle(item.severity);
    final audit = item.audit;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: style.color.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
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
                    color: style.color,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(style.icon, size: 16, color: style.color),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.whatHappened,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        height: 1.2,
                                      ),
                                ),
                              ),
                              OperationalMetricChip(
                                label: 'P${item.priorityScore}',
                                color: style.color,
                                background: style.background,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              OperationalMetricChip(
                                label: style.label,
                                icon: style.icon,
                                color: style.color,
                                background: style.background,
                              ),
                              if (audit != null)
                                OperationalMetricChip(
                                  label: AutomationUiHelpers.confidenceShort(
                                      audit.confidence),
                                  icon: Icons.insights_outlined,
                                  color: AppColors.info,
                                  background: AppColors.infoLight,
                                ),
                              if (item.occurrenceCount > 1)
                                OperationalMetricChip(
                                  label: 'تكرر ${item.occurrenceCount}×',
                                  icon: Icons.repeat_rounded,
                                ),
                              if (AutomationUiHelpers.isFresh(
                                  item.lastRefreshedAt))
                                const OperationalMetricChip(
                                  label: 'جديد',
                                  icon: Icons.fiber_new_rounded,
                                  color: AppColors.success,
                                  background: AppColors.successLight,
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'لماذا: ${item.whyDetected}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 11.5,
                                      height: 1.25,
                                    ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: style.background.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'الخطوة التالية: ${item.nextStep}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                            ),
                          ),
                          if (item.lastRefreshedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'آخر تحديث ${AutomationUiHelpers.relativeTimeAr(item.lastRefreshedAt)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.textHint,
                                    fontSize: 10.5,
                                  ),
                            ),
                          ],
                          if (item.actionRoute != null) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => OperationsNavigation.navigate(
                                    context, item.actionRoute),
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  minimumSize: const Size(0, 28),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  textStyle: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                                icon: const Icon(Icons.arrow_back_rounded,
                                    size: 14),
                                label: const Text('عرض التفاصيل'),
                              ),
                            ),
                          ],
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
}
