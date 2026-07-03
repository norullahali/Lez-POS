import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_favorite.dart';
import '../../widgets/dashboard_favorites_builder.dart';
import 'dashboard_favorite_card.dart';

/// Favorites section — static presentation catalog (Phase 5.5).
///
/// **Ownership:** mounted by [FinancialDashboardScreen] below Notifications
/// and above Dashboard Filters.
///
/// **Presentation boundary:** no providers, no repositories, no persistence,
/// no permissions — placeholder SnackBar only on card tap.
///
/// **Outside personalization:** fixed placement; not toggled by
/// [DashboardPersonalization] (intentional foundation deferral).
///
/// **Outside export:** not included in [DashboardExportDocument] scope.
///
/// **Responsive layout:** [LayoutBuilder] selects 2 or 3 grid columns at
/// [_kGridBreakpoint]; grid is non-scrollable ([shrinkWrap] + locked physics).
///
/// **Rebuild scope:** [StatelessWidget] — rebuilds when the parent rebuilds;
/// catalog re-read from [DashboardFavoritesBuilder.build] each build
/// (O(1) const list, no provider subscriptions).
///
/// **Future navigation:** card [onTap] injection point — screen/section will
/// wire routes when pinning and navigation are implemented.
class DashboardFavoritesSection extends StatelessWidget {
  const DashboardFavoritesSection({super.key});

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static const _kSectionTitle = '\u0627\u0644\u0645\u0641\u0636\u0644\u0629';
  static const _kTitleBottomGap = 8.0;
  static const _kGridBreakpoint = 720.0;
  static const _kCrossAxisSpacing = 12.0;
  static const _kMainAxisSpacing = 12.0;
  static const _kChildAspectRatio = 2.8;

  /// Arabic placeholder suffix appended after the favorite title on tap.
  static const _kComingSoonSuffix = '\u2014 \u0642\u0631\u064a\u0628\u0627\u064b';

  @override
  Widget build(BuildContext context) {
    // O(1) static catalog — no providers, no async work.
    final favorites = DashboardFavoritesBuilder.build();

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
              itemCount: favorites.length,
              itemBuilder: (context, index) {
                final favorite = favorites[index];
                return DashboardFavoriteCard(
                  favorite: favorite,
                  onTap: favorite.enabled
                      ? () => _showPlaceholderFeedback(context, favorite)
                      : null,
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// Foundation placeholder — confirms tap without navigation or pinning mutation.
  static void _showPlaceholderFeedback(
    BuildContext context,
    DashboardFavorite favorite,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${favorite.title} $_kComingSoonSuffix'),
      ),
    );
  }
}