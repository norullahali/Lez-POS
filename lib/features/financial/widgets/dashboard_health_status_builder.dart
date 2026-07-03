import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/dashboard_health_status.dart';

/// Assembles static Financial Dashboard health / system status items (Phase 5.6).
///
/// **Ownership:** invoked by [DashboardHealthStatusSection] at build time.
///
/// **Presentation boundary:** returns a fixed catalog — no backend, monitoring
/// engine, diagnostics, repository access, SQL, or provider reads.
///
/// **Static catalog:** [build] always returns the same six entries in fixed
/// order (database → backup → sync → services → data integrity → system
/// readiness). Catalog content is not live-monitored in this phase.
///
/// **Deterministic ordering:** catalog order matches [DashboardHealthStatusId]
/// declaration order and Phase 5.6 certified sample list.
///
/// **Status mapping:** [statusAccentFor] and [statusLabelAr] cover all four
/// [DashboardSystemStatus] values including [DashboardSystemStatus.offline],
/// even though the demo catalog does not currently display an offline item.
///
/// **Future catalog extension:** add entries here and extend
/// [DashboardHealthStatusId] — no repository or provider changes required
/// until a monitoring engine is wired.
///
/// **Complexity:** O(1) — [kCatalogLength] fixed entries via static list literal.
class DashboardHealthStatusBuilder {
  DashboardHealthStatusBuilder._();

  /// Certified catalog size — must match [build] entry count.
  static const int kCatalogLength = 6;

  // DateTime is not a const constructor — static finals preserve stable demo
  // timestamps without runtime allocation per build.
  static final DateTime _t1 = DateTime(2026, 7, 3, 9, 0);
  static final DateTime _t2 = DateTime(2026, 7, 3, 8, 45);
  static final DateTime _t3 = DateTime(2026, 7, 3, 8, 30);
  static final DateTime _t4 = DateTime(2026, 7, 3, 8, 15);
  static final DateTime _t5 = DateTime(2026, 7, 3, 8, 0);
  static final DateTime _t6 = DateTime(2026, 7, 3, 7, 50);

  /// Builds the certified health status catalog for the dashboard.
  ///
  /// Does not mutate global state, probe services, or read runtime configuration.
  static List<DashboardHealthStatusItem> build() => [
        DashboardHealthStatusItem(
          id: DashboardHealthStatusId.database,
          title: '\u0642\u0627\u0639\u062f\u0629 \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a',
          subtitle: '\u0627\u062a\u0635\u0627\u0644 \u0642\u0627\u0639\u062f\u0629 \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a \u0646\u0634\u0637',
          status: DashboardSystemStatus.healthy,
          icon: Icons.storage_rounded,
          accentColor: AppColors.success,
          timestamp: _t1,
        ),
        DashboardHealthStatusItem(
          id: DashboardHealthStatusId.backup,
          title: '\u0627\u0644\u0646\u0633\u062e \u0627\u0644\u0627\u062d\u062a\u064a\u0627\u0637\u064a',
          subtitle: '\u0622\u062e\u0631 \u0646\u0633\u062e\u0629 \u0627\u062d\u062a\u064a\u0627\u0644\u064a\u0629 \u0646\u062c\u062d\u062a \u0627\u0644\u0644\u064a\u0644\u0629',
          status: DashboardSystemStatus.healthy,
          icon: Icons.backup_rounded,
          accentColor: AppColors.info,
          timestamp: _t2,
        ),
        DashboardHealthStatusItem(
          id: DashboardHealthStatusId.sync,
          title: '\u0627\u0644\u0645\u0632\u0627\u0645\u0646\u0629',
          subtitle: '\u062a\u0623\u062e\u064a\u0631 \u0637\u0641\u064a\u0641 \u0641\u064a \u0645\u0632\u0627\u0645\u0646\u0629 \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a',
          status: DashboardSystemStatus.warning,
          icon: Icons.sync_rounded,
          accentColor: AppColors.warning,
          timestamp: _t3,
        ),
        DashboardHealthStatusItem(
          id: DashboardHealthStatusId.services,
          title: '\u0627\u0644\u062e\u062f\u0645\u0627\u062a',
          subtitle: '\u062c\u0645\u064a\u0639 \u0627\u0644\u062e\u062f\u0645\u0627\u062a \u0627\u0644\u0645\u062d\u0644\u064a\u0629 \u062a\u0639\u0645\u0644',
          status: DashboardSystemStatus.healthy,
          icon: Icons.dns_rounded,
          accentColor: AppColors.primary,
          timestamp: _t4,
        ),
        DashboardHealthStatusItem(
          id: DashboardHealthStatusId.dataIntegrity,
          title: '\u0633\u0644\u0627\u0645\u0629 \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a',
          subtitle: '\u0644\u0627 \u062a\u0648\u062c\u062f \u062a\u0646\u0627\u0642\u0636\u0627\u062a \u0645\u0627\u0644\u064a\u0629 \u0645\u0643\u062a\u0634\u0641\u0629',
          status: DashboardSystemStatus.healthy,
          icon: Icons.verified_user_rounded,
          accentColor: AppColors.success,
          timestamp: _t5,
        ),
        DashboardHealthStatusItem(
          id: DashboardHealthStatusId.systemReadiness,
          title: '\u062c\u0627\u0647\u0632\u064a\u0629 \u0627\u0644\u0646\u0638\u0627\u0645',
          subtitle: '\u062a\u0642\u064a\u064a\u0645 \u0627\u0644\u062c\u0627\u0647\u0632\u064a\u0629 \u0642\u064a\u062f \u0627\u0644\u0627\u0646\u062a\u0638\u0627\u0631',
          status: DashboardSystemStatus.unknown,
          icon: Icons.monitor_heart_rounded,
          accentColor: AppColors.textSecondary,
          timestamp: _t6,
        ),
      ];

  /// Maps [DashboardSystemStatus] to certified accent color for bar and chip.
  static Color statusAccentFor(DashboardSystemStatus status) => switch (status) {
        DashboardSystemStatus.healthy => AppColors.success,
        DashboardSystemStatus.warning => AppColors.warning,
        DashboardSystemStatus.offline => AppColors.error,
        DashboardSystemStatus.unknown => AppColors.textSecondary,
      };

  /// Maps [DashboardSystemStatus] to Arabic label for the status chip.
  static String statusLabelAr(DashboardSystemStatus status) => switch (status) {
        DashboardSystemStatus.healthy => '\u0633\u0644\u064a\u0645',
        DashboardSystemStatus.warning => '\u062a\u062d\u0630\u064a\u0631',
        DashboardSystemStatus.offline => '\u063a\u064a\u0631 \u0645\u062a\u0635\u0644',
        DashboardSystemStatus.unknown => '\u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641',
      };
}
