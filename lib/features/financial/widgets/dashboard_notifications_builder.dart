import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/dashboard_notification.dart';

/// Assembles static Financial Dashboard notifications (Phase 5.4).
///
/// **Ownership:** invoked by [DashboardNotificationsSection] at build time.
///
/// **Presentation boundary:** returns a fixed catalog — no backend, no
/// notification engine, no repository access, no SQL, no provider reads.
///
/// **Static catalog:** [build] always returns the same five entries in the
/// same newest-first order. Catalog content is not user-configurable in this
/// phase.
///
/// **Deterministic ordering:** newest-first by [DashboardNotification.timestamp]
/// (`_t1` through `_t5` descending).
///
/// **Non-const catalog:** [DateTime] anchors are `static final` (not `const`)
/// because Dart `DateTime` constructors are not const expressions. The list
/// literal is still O(1) with fixed size — rebuild cost is negligible.
///
/// **Complexity:** O(1) — [kCatalogLength] fixed entries; [accentFor] / [iconFor]
/// are O(1) switches.
class DashboardNotificationsBuilder {
  DashboardNotificationsBuilder._();

  /// Certified catalog size — must match [build] entry count.
  static const int kCatalogLength = 5;

  // Fixed presentation timestamps — static final because DateTime() is not const.
  static final DateTime _t1 = DateTime(2026, 6, 26, 9, 15);
  static final DateTime _t2 = DateTime(2026, 6, 26, 8, 40);
  static final DateTime _t3 = DateTime(2026, 6, 25, 17, 30);
  static final DateTime _t4 = DateTime(2026, 6, 25, 11, 5);
  static final DateTime _t5 = DateTime(2026, 6, 24, 14, 0);

  /// Builds the certified notification catalog for the dashboard.
  ///
  /// Does not mutate global state or read runtime configuration.
  static List<DashboardNotification> build() => [
        DashboardNotification(
          id: 'notif_cash_flow_review',
          title: '\u062a\u0646\u0628\u064a\u0647: \u0645\u0631\u0627\u062c\u0639\u0629 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
          message:
              '\u064a\u0648\u062c\u062f \u0627\u0646\u062e\u0641\u0627\u0636 \u0641\u064a \u0635\u0627\u0641\u064a \u0627\u0644\u0646\u0634\u0627\u0637 \u0627\u0644\u062a\u062c\u0627\u0631\u064a \u0644\u0647\u0630\u0627 \u0627\u0644\u0623\u0633\u0628\u0648\u0639.',
          severity: DashboardNotificationSeverity.warning,
          timestamp: _t1,
        ),
        DashboardNotification(
          id: 'notif_monthly_summary',
          title: '\u0645\u0644\u062e\u0635 \u0627\u0644\u0623\u062f\u0627\u0621 \u0627\u0644\u0645\u0627\u0644\u064a \u062c\u0627\u0647\u0632',
          message:
              '\u062a\u0645 \u0625\u0639\u062f\u0627\u062f \u0645\u0644\u062e\u0635 \u0627\u0644\u064a\u0648\u0645 \u0644\u0644\u0648\u062d\u0629 \u0627\u0644\u0645\u0627\u0644\u064a\u0629.',
          severity: DashboardNotificationSeverity.info,
          timestamp: _t2,
        ),
        DashboardNotification(
          id: 'notif_export_complete',
          title: '\u0627\u0643\u062a\u0645\u0644 \u062a\u0635\u062f\u064a\u0631 \u0627\u0644\u062a\u0642\u0631\u064a\u0631',
          message:
              '\u062a\u0645 \u062d\u0641\u0638 \u062a\u0642\u0631\u064a\u0631 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a \u0628\u0646\u062c\u0627\u062d.',
          severity: DashboardNotificationSeverity.success,
          timestamp: _t3,
          isRead: true,
        ),
        DashboardNotification(
          id: 'notif_receivables_reminder',
          title: '\u062a\u0630\u0643\u064a\u0631: \u0645\u062a\u0627\u0628\u0639\u0629 \u0627\u0644\u0630\u0645\u0645 \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
          message:
              '\u0647\u0646\u0627\u0643 \u062d\u0633\u0627\u0628\u0627\u062a \u0639\u0645\u0644\u0627\u0621 \u062a\u062d\u062a\u0627\u062c \u0645\u0631\u0627\u062c\u0639\u0629 \u0641\u0648\u0631\u064a\u0629.',
          severity: DashboardNotificationSeverity.info,
          timestamp: _t4,
          isRead: true,
        ),
        DashboardNotification(
          id: 'notif_expense_threshold',
          title: '\u062a\u0646\u0628\u064a\u0647: \u0627\u0631\u062a\u0641\u0627\u0639 \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a',
          message:
              '\u062a\u062c\u0627\u0648\u0632\u062a \u0645\u0635\u0631\u0648\u0641\u0627\u062a \u0627\u0644\u0634\u0647\u0631 \u0627\u0644\u062d\u0627\u0644\u064a \u0627\u0644\u062d\u062f \u0627\u0644\u0645\u0639\u062a\u0645\u062f \u0644\u0644\u0641\u0626\u0629.',
          severity: DashboardNotificationSeverity.error,
          timestamp: _t5,
        ),
      ];

  /// Presentation accent color per severity — UI styling only, not business rules.
  ///
  /// Used by [DashboardNotificationCard] for left border and icon container tint.
  static Color accentFor(DashboardNotificationSeverity severity) =>
      switch (severity) {
        DashboardNotificationSeverity.info => AppColors.info,
        DashboardNotificationSeverity.success => AppColors.success,
        DashboardNotificationSeverity.warning => AppColors.warning,
        DashboardNotificationSeverity.error => AppColors.error,
      };

  /// Material icon per severity — presentation only.
  ///
  /// Used by [DashboardNotificationCard] for the leading icon container.
  static IconData iconFor(DashboardNotificationSeverity severity) =>
      switch (severity) {
        DashboardNotificationSeverity.info => Icons.info_outline_rounded,
        DashboardNotificationSeverity.success => Icons.check_circle_outline_rounded,
        DashboardNotificationSeverity.warning => Icons.warning_amber_rounded,
        DashboardNotificationSeverity.error => Icons.error_outline_rounded,
      };
}