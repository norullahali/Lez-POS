import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_favorite.dart';

/// Tappable favorite card — matches Financial Dashboard tile styling.
///
/// **Ownership:** rendered by [DashboardFavoritesSection]; does not resolve
/// navigation, permissions, or pinning persistence.
///
/// **Read-only policy:** displays [DashboardFavorite] metadata only — does not
/// mutate financial data, filters, or provider state.
///
/// **Callback boundary:** [onTap] is injected by the parent section. This widget
/// never calls `Navigator`, routing APIs, or repositories.
///
/// **Enabled/disabled:** interactive when [DashboardFavorite.enabled] is true
/// and [onTap] is non-null; otherwise [InkWell] is disabled and opacity reduced.
///
/// **RTL:** star trailing indicator suits Arabic RTL layouts; text uses natural
/// reading order without directionality overrides.
///
/// **Accessibility:** title and subtitle use ellipsis overflow; future phases
/// may add `Semantics` labels when navigation is wired.
class DashboardFavoriteCard extends StatelessWidget {
  const DashboardFavoriteCard({
    super.key,
    required this.favorite,
    this.onTap,
  });

  /// Display descriptor supplied by [DashboardFavoritesBuilder].
  final DashboardFavorite favorite;

  /// Tap handler injected by parent; foundation uses SnackBar placeholder only.
  final VoidCallback? onTap;

  static const _kHorizontalPadding = 16.0;
  static const _kVerticalPadding = 14.0;
  static const _kIconContainerSize = 40.0;
  static const _kIconSize = 22.0;
  static const _kIconBorderRadius = 10.0;
  static const _kAccentAlpha = 0.12;
  static const _kIconGap = 12.0;
  static const _kTitleFontSize = 13.0;
  static const _kSubtitleFontSize = 11.0;
  static const _kSubtitleLineHeight = 1.3;
  static const _kTitleSubtitleGap = 4.0;
  static const _kStarSize = 16.0;
  static const _kDisabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    final enabled = favorite.enabled && onTap != null;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : _kDisabledOpacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _kHorizontalPadding,
              vertical: _kVerticalPadding,
            ),
            child: Row(
              children: [
                Container(
                  width: _kIconContainerSize,
                  height: _kIconContainerSize,
                  decoration: BoxDecoration(
                    color: favorite.accentColor.withValues(alpha: _kAccentAlpha),
                    borderRadius: BorderRadius.circular(_kIconBorderRadius),
                  ),
                  child: Icon(
                    favorite.icon,
                    color: favorite.accentColor,
                    size: _kIconSize,
                  ),
                ),
                const SizedBox(width: _kIconGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        favorite.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: _kTitleFontSize,
                            ),
                      ),
                      const SizedBox(height: _kTitleSubtitleGap),
                      Text(
                        favorite.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: _kSubtitleFontSize,
                              height: _kSubtitleLineHeight,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.star_rounded,
                  size: _kStarSize,
                  color: enabled ? favorite.accentColor : AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}