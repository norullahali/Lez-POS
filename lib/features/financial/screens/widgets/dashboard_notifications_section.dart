import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_notification.dart';
import '../../widgets/dashboard_notifications_builder.dart';
import 'dashboard_notification_card.dart';

/// Notifications Center section — static presentation catalog (Phase 5.4).
///
/// **Ownership:** mounted by [FinancialDashboardScreen] below Quick Actions
/// and above Dashboard Filters.
///
/// **Presentation boundary:** no providers, no repositories, no notification
/// engine, no persistence — placeholder SnackBar only on card tap.
///
/// **Outside personalization:** fixed placement; not toggled by
/// [DashboardPersonalization] (intentional foundation deferral).
///
/// **Outside export:** not included in [DashboardExportDocument] scope.
///
/// **Static read/unread:** [DashboardNotification.isRead] is set in the builder
/// catalog for presentation demo only — tap does not mutate read state.
///
/// **Rebuild scope:** [StatelessWidget] — rebuilds when the parent rebuilds;
/// catalog re-read from [DashboardNotificationsBuilder.build] each build
/// (O(1), no provider subscriptions).
class DashboardNotificationsSection extends StatelessWidget {
  const DashboardNotificationsSection({super.key});

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static const _kSectionTitle = '\u0645\u0631\u0643\u0632 \u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a';
  static const _kTitleBottomGap = 8.0;
  static const _kCardSpacing = 10.0;
  static const _kComingSoonSuffix = '\u2014 \u0642\u0631\u064a\u0628\u0627\u064b';

  @override
  Widget build(BuildContext context) {
    // O(1) static catalog — no providers, no async work.
    final notifications = DashboardNotificationsBuilder.build();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          _kSectionTitle,
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: _kTitleBottomGap),
        ...notifications.map(
          (notification) => Padding(
            padding: const EdgeInsets.only(bottom: _kCardSpacing),
            child: DashboardNotificationCard(
              notification: notification,
              onTap: () => _showPlaceholderFeedback(context, notification),
            ),
          ),
        ),
      ],
    );
  }

  /// Foundation placeholder — confirms tap without navigation or read-state mutation.
  static void _showPlaceholderFeedback(
    BuildContext context,
    DashboardNotification notification,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${notification.title} $_kComingSoonSuffix'),
      ),
    );
  }
}