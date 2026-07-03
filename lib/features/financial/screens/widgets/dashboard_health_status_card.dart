import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_health_status.dart';
import '../../widgets/dashboard_health_status_builder.dart';

/// Tappable health status card — matches Financial Dashboard card styling.
///
/// **Ownership:** rendered by [DashboardHealthStatusSection]; does not resolve
/// navigation, monitoring probes, or diagnostics.
///
/// **Read-only policy:** displays [DashboardHealthStatusItem] metadata only —
/// does not mutate financial data, filters, or provider state.
///
/// **Callback boundary:** [onTap] is injected by the parent section. This widget
/// never calls `Navigator`, routing APIs, repositories, or providers.
///
/// **Status chip:** right-side chip shows Arabic label from
/// [DashboardHealthStatusBuilder.statusLabelAr]; left accent bar uses
/// [DashboardHealthStatusBuilder.statusAccentFor] — not live monitoring logic.
///
/// **RTL:** Column/Row layout with Arabic text; status chip trailing suits RTL;
/// no directionality overrides.
///
/// **Accessibility:** title uses ellipsis overflow; future phases may add
/// `Semantics` labels when monitoring navigation is wired.
class DashboardHealthStatusCard extends StatelessWidget {
  const DashboardHealthStatusCard({
    super.key,
    required this.item,
    this.onTap,
  });

  /// Display descriptor supplied by [DashboardHealthStatusBuilder].
  final DashboardHealthStatusItem item;

  /// Tap handler injected by parent; foundation uses SnackBar placeholder only.
  final VoidCallback? onTap;

  static const _kAccentBorderWidth = 4.0;
  static const _kCardPaddingHorizontal = 16.0;
  static const _kCardPaddingVertical = 14.0;
  static const _kIconContainerSize = 40.0;
  static const _kIconSize = 22.0;
  static const _kIconBorderRadius = 10.0;
  static const _kAccentAlpha = 0.12;
  static const _kIconTextGap = 12.0;
  static const _kTitleBodyGap = 6.0;
  static const _kBodyTimestampGap = 8.0;
  static const _kStatusChipHorizontalPadding = 8.0;
  static const _kStatusChipVerticalPadding = 4.0;
  static const _kStatusChipGap = 8.0;
  static const _kTitleFontSize = 13.0;
  static const _kSubtitleFontSize = 12.0;
  static const _kSubtitleLineHeight = 1.45;
  static const _kTimestampFontSize = 11.0;
  static const _kStatusFontSize = 11.0;

  static final _timestampFormat = DateFormat('yyyy/MM/dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final statusColor =
        DashboardHealthStatusBuilder.statusAccentFor(item.status);
    final statusLabel =
        DashboardHealthStatusBuilder.statusLabelAr(item.status);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: _kAccentBorderWidth, color: statusColor),
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
                          color: item.accentColor.withValues(alpha: _kAccentAlpha),
                          borderRadius:
                              BorderRadius.circular(_kIconBorderRadius),
                        ),
                        child: Icon(
                          item.icon,
                          color: item.accentColor,
                          size: _kIconSize,
                        ),
                      ),
                      const SizedBox(width: _kIconTextGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: _kTitleFontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: _kTitleBodyGap),
                            Text(
                              item.subtitle,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: _kSubtitleFontSize,
                                height: _kSubtitleLineHeight,
                              ),
                            ),
                            const SizedBox(height: _kBodyTimestampGap),
                            Text(
                              _timestampFormat.format(item.timestamp),
                              style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: _kTimestampFontSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: _kStatusChipGap),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _kStatusChipHorizontalPadding,
                          vertical: _kStatusChipVerticalPadding,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: _kAccentAlpha),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: _kStatusFontSize,
                            fontWeight: FontWeight.w700,
                          ),
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
    );
  }
}
