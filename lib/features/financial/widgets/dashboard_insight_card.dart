import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'dashboard_analytics_insight.dart';

/// Read-only insight card for the Financial Dashboard (Phase 5.3.4).
///
/// **Read-only policy:** no [InkWell], buttons, drill-down, dialogs, or edits.
///
/// **Ownership:** stateless display widget; parent [_InsightsList] owns the list.
///
/// Visual layout matches [DashboardKpiTile] icon + text pattern for consistency.
class DashboardInsightCard extends StatelessWidget {
  const DashboardInsightCard({super.key, required this.insight});

  final DashboardAnalyticsInsight insight;

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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: insight.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(insight.icon, color: insight.accentColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle,
                  ),
                  const SizedBox(height: 6),
                  Text(insight.body, style: _bodyStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
