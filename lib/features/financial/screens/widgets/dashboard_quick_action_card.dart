import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_quick_action.dart';
import '../../widgets/dashboard_quick_actions_builder.dart';

/// Tappable quick action card — matches Financial Dashboard tile styling.
///
/// **Ownership:** rendered by [DashboardQuickActionsSection]; does not resolve
/// navigation or permissions.
///
/// **Callback boundary:** [onTap] is injected by the parent section. This
/// widget never calls `Navigator`, routing APIs, or repositories.
///
/// **Enabled/disabled:** interactive when [DashboardQuickAction.enabled] is
/// true and [onTap] is non-null; otherwise [InkWell] is disabled and opacity
/// is reduced.
///
/// **RTL:** chevron uses [Icons.arrow_back_ios_new_rounded] — forward cue in
/// Arabic RTL layouts (points toward reading direction).
class DashboardQuickActionCard extends StatelessWidget {
  const DashboardQuickActionCard({
    super.key,
    required this.action,
    this.onTap,
  });

  /// Display descriptor supplied by [DashboardQuickActionsBuilder].
  final DashboardQuickAction action;

  /// Tap handler injected by parent; null disables interaction.
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
  static const _kChevronSize = 14.0;
  static const _kDisabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    final accent = DashboardQuickActionsBuilder.accentFor(action.id);
    final enabled = action.enabled && onTap != null;

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
                    color: accent.withValues(alpha: _kAccentAlpha),
                    borderRadius: BorderRadius.circular(_kIconBorderRadius),
                  ),
                  child: Icon(action.icon, color: accent, size: _kIconSize),
                ),
                const SizedBox(width: _kIconGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        action.title,
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
                        action.subtitle,
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
                  Icons.arrow_back_ios_new_rounded,
                  size: _kChevronSize,
                  color: enabled
                      ? AppColors.textSecondary
                      : AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}