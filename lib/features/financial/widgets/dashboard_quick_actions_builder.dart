import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/dashboard_quick_action.dart';

/// Assembles static Financial Dashboard quick actions (Phase 5.3.8).
///
/// **Ownership:** invoked by [DashboardQuickActionsSection] at build time.
///
/// **Presentation boundary:** returns a fixed catalog of action descriptors —
/// no permissions, no repository access, no SQL, no provider reads.
///
/// **Deterministic ordering:** catalog order is fixed (cash ledger → reports →
/// customers → suppliers → sales → purchases). Same call always yields the
/// same list reference semantics via const list literal.
///
/// **Complexity:** O(1) — six fixed entries; [accentFor] is O(1) switch.
class DashboardQuickActionsBuilder {
  DashboardQuickActionsBuilder._();

  /// Certified catalog size — must match [build] entry count.
  static const int kCatalogLength = 6;

  /// Builds the certified quick action catalog for the dashboard.
  ///
  /// Does not mutate global state or read runtime configuration.
  static List<DashboardQuickAction> build() => const [
        DashboardQuickAction(
          id: DashboardQuickActionId.cashLedger,
          title: '\u062f\u0641\u062a\u0631 \u0627\u0644\u0646\u0642\u062f\u064a\u0629',
          subtitle: '\u0639\u0631\u0636 \u062d\u0631\u0643\u0629 \u0627\u0644\u0646\u0642\u062f',
          icon: Icons.account_balance_wallet_rounded,
        ),
        DashboardQuickAction(
          id: DashboardQuickActionId.financialReports,
          title: '\u0627\u0644\u062a\u0642\u0627\u0631\u064a\u0631 \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
          subtitle: '\u0641\u062a\u062d \u0645\u0631\u0643\u0632 \u0627\u0644\u062a\u0642\u0627\u0631\u064a\u0631',
          icon: Icons.assessment_rounded,
        ),
        DashboardQuickAction(
          id: DashboardQuickActionId.customers,
          title: '\u0627\u0644\u0639\u0645\u0644\u0627\u0621',
          subtitle: '\u0625\u062f\u0627\u0631\u0629 \u062d\u0633\u0627\u0628\u0627\u062a \u0627\u0644\u0639\u0645\u0644\u0627\u0621',
          icon: Icons.people_rounded,
        ),
        DashboardQuickAction(
          id: DashboardQuickActionId.suppliers,
          title: '\u0627\u0644\u0645\u0648\u0631\u062f\u0648\u0646',
          subtitle: '\u0625\u062f\u0627\u0631\u0629 \u062d\u0633\u0627\u0628\u0627\u062a \u0627\u0644\u0645\u0648\u0631\u062f\u064a\u0646',
          icon: Icons.local_shipping_rounded,
        ),
        DashboardQuickAction(
          id: DashboardQuickActionId.sales,
          title: '\u0627\u0644\u0645\u0628\u064a\u0639\u0627\u062a',
          subtitle: '\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0646\u0634\u0627\u0637',
          icon: Icons.point_of_sale_rounded,
        ),
        DashboardQuickAction(
          id: DashboardQuickActionId.purchases,
          title: '\u0627\u0644\u0645\u0634\u062a\u0631\u064a\u0627\u062a',
          subtitle: '\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0645\u0634\u062a\u0631\u064a\u0627\u062a \u0627\u0644\u0645\u062e\u0632\u0648\u0646',
          icon: Icons.shopping_cart_rounded,
        ),
      ];

  /// Presentation accent color per action — UI styling only, not business rules.
  ///
  /// Used by [DashboardQuickActionCard] for icon container tinting.
  static Color accentFor(DashboardQuickActionId id) => switch (id) {
        DashboardQuickActionId.cashLedger => AppColors.primary,
        DashboardQuickActionId.financialReports => AppColors.info,
        DashboardQuickActionId.customers => AppColors.success,
        DashboardQuickActionId.suppliers => AppColors.warning,
        DashboardQuickActionId.sales => AppColors.primary,
        DashboardQuickActionId.purchases => AppColors.error,
      };
}
