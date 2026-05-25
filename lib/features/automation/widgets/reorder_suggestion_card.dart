import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/reorder_suggestion.dart';
import 'automation_ui_helpers.dart';
import 'operational_metric_chip.dart';

class ReorderSuggestionCard extends StatefulWidget {
  const ReorderSuggestionCard({super.key, required this.suggestion});
  final ReorderSuggestion suggestion;

  @override
  State<ReorderSuggestionCard> createState() => _ReorderSuggestionCardState();
}

class _ReorderSuggestionCardState extends State<ReorderSuggestionCard> {
  bool _hovered = false;

  ReorderSuggestion get s => widget.suggestion;

  @override
  Widget build(BuildContext context) {
    final style = AutomationUiHelpers.reorderUrgencyStyle(s.urgency);

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
                  ? [BoxShadow(color: style.color.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 4, color: style.color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySurface,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'طلب: ${s.suggestedQty.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
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
                              OperationalMetricChip(
                                label: 'P${s.priorityScore}',
                                color: style.color,
                                background: style.background,
                              ),
                              OperationalMetricChip(
                                label: 'مخزون ${s.currentStock.toStringAsFixed(0)}',
                                icon: Icons.inventory_2_outlined,
                              ),
                              OperationalMetricChip(
                                label: '${s.daysRemaining.toStringAsFixed(0)} يوم',
                                icon: Icons.timelapse_outlined,
                              ),
                              OperationalMetricChip(
                                label: '${s.dailyRate.toStringAsFixed(1)}/يوم',
                                icon: Icons.speed_outlined,
                              ),
                              if (s.supplierName != null)
                                OperationalMetricChip(
                                  label: s.supplierName!,
                                  icon: Icons.local_shipping_outlined,
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            s.explanation,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 11.5,
                                  height: 1.25,
                                ),
                          ),
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