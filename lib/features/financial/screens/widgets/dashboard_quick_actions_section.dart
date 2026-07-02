import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_quick_action.dart';
import '../../widgets/dashboard_quick_actions_builder.dart';
import 'dashboard_quick_action_card.dart';

/// Quick Actions section — static presentation catalog (Phase 5.3.8).
///
/// **Ownership:** mounted by [FinancialDashboardScreen] below the header.
/// Does not participate in personalization or export.
///
/// **Presentation boundary:** no providers, no repositories, no navigation —
/// placeholder SnackBar only on card tap.
///
/// **Responsive layout:** [LayoutBuilder] selects 2 or 3 grid columns at
/// [_kGridBreakpoint]; grid is non-scrollable ([shrinkWrap] + locked physics).
///
/// **Rebuild scope:** [StatelessWidget] — rebuilds only when the parent
/// rebuilds; catalog is re-read from [DashboardQuickActionsBuilder.build] each
/// build (O(1) const list, no provider subscriptions).
class DashboardQuickActionsSection extends StatelessWidget {
  const DashboardQuickActionsSection({super.key});

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static const _kSectionTitle = '\u0627\u0644\u0625\u062c\u0631\u0627\u0621\u0627\u062a \u0627\u0644\u0633\u0631\u064a\u0639\u0629';
  static const _kTitleBottomGap = 8.0;
  static const _kGridBreakpoint = 720.0;
  static const _kCrossAxisSpacing = 12.0;
  static const _kMainAxisSpacing = 12.0;
  static const _kChildAspectRatio = 2.8;

  /// Arabic placeholder suffix appended after the action title on tap.
  static const _kComingSoonSuffix = '\u2014 \u0642\u0631\u064a\u0628\u0627\u064b';

  @override
  Widget build(BuildContext context) {
    final actions = DashboardQuickActionsBuilder.build();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          _kSectionTitle,
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: _kTitleBottomGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount =
                constraints.maxWidth >= _kGridBreakpoint ? 3 : 2;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: _kCrossAxisSpacing,
                mainAxisSpacing: _kMainAxisSpacing,
                childAspectRatio: _kChildAspectRatio,
              ),
              itemCount: actions.length,
              itemBuilder: (context, index) {
                final action = actions[index];
                return DashboardQuickActionCard(
                  action: action,
                  onTap: action.enabled
                      ? () => _showPlaceholderFeedback(context, action)
                      : null,
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// Foundation placeholder — confirms tap without navigation (Phase 5.3.9+).
  static void _showPlaceholderFeedback(
    BuildContext context,
    DashboardQuickAction action,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${action.title} $_kComingSoonSuffix'),
      ),
    );
  }
}
