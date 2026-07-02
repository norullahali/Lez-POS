import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_personalization.dart';

/// Wraps a dashboard section with presentation-only collapse chrome (Phase 5.3.6).
///
/// **Ownership:** invoked by [FinancialDashboardScreen._personalizedSection] only.
///
/// **Widget boundary:** does not modify [child] internals; adds collapse chrome only.
///
/// **Mounted/unmounted behavior:** when [collapsed] is true, [child] is omitted
/// from the element tree — section [ConsumerWidget] children do not subscribe to
/// providers. When expanded, [child] mounts normally.
///
/// Does not affect repository calls, provider invalidation, or financial data.
class DashboardPersonalizedSection extends StatelessWidget {
  const DashboardPersonalizedSection({
    super.key,
    required this.sectionId,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.child,
  });

  final DashboardSectionId sectionId;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final Widget child;

  static const _kCollapsedTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          title: Text(sectionId.labelAr, style: _kCollapsedTitleStyle),
          trailing: IconButton(
            tooltip: '\u062a\u0648\u0633\u064a\u0639',
            icon: const Icon(Icons.expand_more_rounded),
            color: AppColors.textSecondary,
            onPressed: onToggleCollapse,
          ),
          onTap: onToggleCollapse,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: IconButton(
            tooltip: '\u0637\u064a',
            icon: const Icon(Icons.expand_less_rounded, size: 20),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: onToggleCollapse,
          ),
        ),
        child,
      ],
    );
  }
}