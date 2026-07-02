import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_notification.dart';
import '../../widgets/dashboard_notifications_builder.dart';

/// Tappable notification card — matches Financial Dashboard card styling.
///
/// **Ownership:** rendered by [DashboardNotificationsSection]; does not resolve
/// navigation, read-state mutation, or notification delivery.
///
/// **Callback boundary:** [onTap] is injected by the parent section. This widget
/// never calls `Navigator`, routing APIs, repositories, or providers.
///
/// **Read/unread presentation:** unread — thicker accent border, unread dot,
/// bold title, full opacity, [AppColors.surface]. Read — muted opacity, no dot,
/// [AppColors.surfaceVariant]. Driven by [DashboardNotification.isRead] only.
///
/// **Severity styling:** left accent bar and icon tint from
/// [DashboardNotificationsBuilder.accentFor] / [iconFor] — not alert logic.
///
/// **RTL:** Column/Row layout with Arabic text; no directionality overrides.
class DashboardNotificationCard extends StatelessWidget {
  const DashboardNotificationCard({
    super.key,
    required this.notification,
    this.onTap,
  });

  /// Display descriptor supplied by [DashboardNotificationsBuilder].
  final DashboardNotification notification;

  /// Tap handler injected by parent; foundation uses SnackBar placeholder only.
  final VoidCallback? onTap;

  static const _kReadAccentBorderWidth = 4.0;
  static const _kUnreadAccentBorderWidth = 6.0;
  static const _kCardPaddingHorizontal = 16.0;
  static const _kCardPaddingVertical = 14.0;
  static const _kIconContainerSize = 40.0;
  static const _kIconSize = 22.0;
  static const _kIconBorderRadius = 10.0;
  static const _kAccentAlpha = 0.12;
  static const _kIconTextGap = 12.0;
  static const _kTitleBodyGap = 6.0;
  static const _kBodyTimestampGap = 8.0;
  static const _kUnreadDotSize = 8.0;
  static const _kUnreadDotGap = 8.0;
  static const _kReadOpacity = 0.72;
  static const _kTitleFontSize = 13.0;
  static const _kMessageFontSize = 12.0;
  static const _kMessageLineHeight = 1.45;
  static const _kTimestampFontSize = 11.0;

  static final _timestampFormat = DateFormat('yyyy/MM/dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final accent =
        DashboardNotificationsBuilder.accentFor(notification.severity);
    final icon =
        DashboardNotificationsBuilder.iconFor(notification.severity);
    final isUnread = !notification.isRead;
    final borderWidth =
        isUnread ? _kUnreadAccentBorderWidth : _kReadAccentBorderWidth;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: isUnread ? AppColors.surface : AppColors.surfaceVariant,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: isUnread ? 1 : _kReadOpacity,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: borderWidth, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kCardPaddingHorizontal,
                      vertical: _kCardPaddingVertical,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: _kIconContainerSize,
                          height: _kIconContainerSize,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: _kAccentAlpha),
                            borderRadius:
                                BorderRadius.circular(_kIconBorderRadius),
                          ),
                          child: Icon(icon, color: accent, size: _kIconSize),
                        ),
                        const SizedBox(width: _kIconTextGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isUnread) ...[
                                    Container(
                                      width: _kUnreadDotSize,
                                      height: _kUnreadDotSize,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: _kUnreadDotGap),
                                  ],
                                  Expanded(
                                    child: Text(
                                      notification.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: _kTitleFontSize,
                                        fontWeight: isUnread
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: _kTitleBodyGap),
                              Text(
                                notification.message,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: _kMessageFontSize,
                                  height: _kMessageLineHeight,
                                ),
                              ),
                              const SizedBox(height: _kBodyTimestampGap),
                              Text(
                                _timestampFormat.format(notification.timestamp),
                                style: const TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: _kTimestampFontSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}