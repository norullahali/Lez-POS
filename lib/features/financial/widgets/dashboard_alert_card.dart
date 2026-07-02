import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'dashboard_financial_alert.dart';

/// Read-only alert card for the Financial Dashboard (Phase 5.3.5).
///
/// **Read-only policy:** no [InkWell], buttons, drill-down, dialogs, or edits.
///
/// **Ownership:** stateless display widget; parent [_AlertsList] owns the list.
///
/// Visually distinct from [DashboardInsightCard] via leading accent border;
/// icon + text pattern otherwise matches dashboard card conventions.
class DashboardAlertCard extends StatelessWidget {
  const DashboardAlertCard({super.key, required this.alert});

  final DashboardFinancialAlert alert;

  static const _kAccentBorderWidth = 4.0;
  static const _kCardPaddingHorizontal = 16.0;
  static const _kCardPaddingVertical = 14.0;
  static const _kIconContainerSize = 40.0;
  static const _kIconSize = 22.0;
  static const _kIconTextGap = 12.0;
  static const _kTitleBodyGap = 6.0;

  static const _titleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  static const _bodyStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
    height: 1.45,
  );

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: _kAccentBorderWidth, color: alert.accentColor),
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
                        color: alert.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        alert.icon,
                        color: alert.accentColor,
                        size: _kIconSize,
                      ),
                    ),
                    const SizedBox(width: _kIconTextGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            alert.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _titleStyle,
                          ),
                          const SizedBox(height: _kTitleBodyGap),
                          Text(alert.body, style: _bodyStyle),
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
    );
  }
}
