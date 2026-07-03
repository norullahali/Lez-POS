import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/dashboard_favorite.dart';

/// Assembles static Financial Dashboard favorites (Phase 5.5).
///
/// **Ownership:** invoked by [DashboardFavoritesSection] at build time.
///
/// **Presentation boundary:** returns a fixed catalog — no backend, no
/// persistence, no permissions, no repository access, no SQL, no provider reads.
///
/// **Static catalog:** [build] always returns the same six entries in fixed
/// order (cash ledger → sales → purchases → reports → customers → suppliers).
/// Catalog content is not user-configurable in this phase.
///
/// **Deterministic ordering:** catalog order matches [DashboardFavoriteId]
/// declaration order and Phase 5.5 certified sample list.
///
/// **Future catalog extension:** add entries here and extend [DashboardFavoriteId]
/// — no repository or provider changes required until pinning engine is wired.
///
/// **Complexity:** O(1) — [kCatalogLength] fixed entries via const list literal.
class DashboardFavoritesBuilder {
  DashboardFavoritesBuilder._();

  /// Certified catalog size — must match [build] entry count.
  static const int kCatalogLength = 6;

  /// Builds the certified favorites catalog for the dashboard.
  ///
  /// Does not mutate global state or read runtime configuration.
  static List<DashboardFavorite> build() => const [
        DashboardFavorite(
          id: DashboardFavoriteId.cashLedger,
          title: '\u062f\u0641\u062a\u0631 \u0627\u0644\u0646\u0642\u062f\u064a\u0629',
          subtitle: '\u0648\u0635\u0644 \u0633\u0631\u064a\u0639 \u0644\u062d\u0631\u0643\u0629 \u0627\u0644\u0646\u0642\u062f',
          icon: Icons.account_balance_wallet_rounded,
          accentColor: AppColors.primary,
        ),
        DashboardFavorite(
          id: DashboardFavoriteId.sales,
          title: '\u0627\u0644\u0645\u0628\u064a\u0639\u0627\u062a',
          subtitle: '\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0646\u0634\u0627\u0637',
          icon: Icons.point_of_sale_rounded,
          accentColor: AppColors.primary,
        ),
        DashboardFavorite(
          id: DashboardFavoriteId.purchases,
          title: '\u0627\u0644\u0645\u0634\u062a\u0631\u064a\u0627\u062a',
          subtitle: '\u0627\u0644\u0627\u0646\u062a\u0642\u0627\u0644 \u0625\u0644\u0649 \u0645\u0634\u062a\u0631\u064a\u0627\u062a \u0627\u0644\u0645\u062e\u0632\u0648\u0646',
          icon: Icons.shopping_cart_rounded,
          accentColor: AppColors.error,
        ),
        DashboardFavorite(
          id: DashboardFavoriteId.financialReports,
          title: '\u0627\u0644\u062a\u0642\u0627\u0631\u064a\u0631',
          subtitle: '\u0641\u062a\u062d \u0645\u0631\u0643\u0632 \u0627\u0644\u062a\u0642\u0627\u0631\u064a\u0631 \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
          icon: Icons.assessment_rounded,
          accentColor: AppColors.info,
        ),
        DashboardFavorite(
          id: DashboardFavoriteId.customers,
          title: '\u0627\u0644\u0639\u0645\u0644\u0627\u0621',
          subtitle: '\u0625\u062f\u0627\u0631\u0629 \u062d\u0633\u0627\u0628\u0627\u062a \u0627\u0644\u0639\u0645\u0644\u0627\u0621',
          icon: Icons.people_rounded,
          accentColor: AppColors.success,
        ),
        DashboardFavorite(
          id: DashboardFavoriteId.suppliers,
          title: '\u0627\u0644\u0645\u0648\u0631\u062f\u0648\u0646',
          subtitle: '\u0625\u062f\u0627\u0631\u0629 \u062d\u0633\u0627\u0628\u0627\u062a \u0627\u0644\u0645\u0648\u0631\u062f\u064a\u0646',
          icon: Icons.local_shipping_rounded,
          accentColor: AppColors.warning,
        ),
      ];
}