import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/dashboard_health_status.dart';
import '../../widgets/dashboard_health_status_builder.dart';
import 'dashboard_health_status_card.dart';

/// Health & system status section — static presentation catalog (Phase 5.6).
///
/// **Ownership:** mounted by [FinancialDashboardScreen] below Favorites
/// and above Dashboard Filters.
///
/// **Presentation boundary:** no providers, no repositories, no monitoring
/// engine, no diagnostics, no persistence — placeholder SnackBar only on tap.
///
/// **Outside personalization:** fixed placement; not toggled by
/// [DashboardPersonalization] (intentional foundation deferral).
///
/// **Outside export:** not included in [DashboardExportDocument] scope.
///
/// **Static catalog:** vertical list of six certified health items from
/// [DashboardHealthStatusBuilder.build] — not live-monitored in this phase.
///
/// **Rebuild scope:** [StatelessWidget] — rebuilds when the parent rebuilds;
/// catalog re-read from [DashboardHealthStatusBuilder.build] each build
/// (O(1) static list, no provider subscriptions).
///
/// **Future monitoring:** card [onTap] injection point — screen/section will
/// wire diagnostics detail routes when a monitoring engine is implemented.
class DashboardHealthStatusSection extends StatelessWidget {
  const DashboardHealthStatusSection({super.key});

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static const _kSectionTitle =
      '\u0635\u062d\u0629 \u0627\u0644\u0646\u0638\u0627\u0645 \u0648\u0627\u0644\u062d\u0627\u0644\u0629';
  static const _kTitleBottomGap = 8.0;
  static const _kCardSpacing = 10.0;

  /// Arabic placeholder suffix appended after the health item title on tap.
  static const _kComingSoonSuffix = '\u2014 \u0642\u0631\u064a\u0628\u0627\u064b';

  @override
  Widget build(BuildContext context) {
    // O(1) static catalog — no providers, no async work, no monitoring probes.
    final items = DashboardHealthStatusBuilder.build();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          _kSectionTitle,
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: _kTitleBottomGap),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: _kCardSpacing),
            child: DashboardHealthStatusCard(
              item: item,
              onTap: () => _showPlaceholderFeedback(context, item),
            ),
          ),
        ),
      ],
    );
  }

  /// Foundation placeholder — no navigation, monitoring, or diagnostics.
  static void _showPlaceholderFeedback(
    BuildContext context,
    DashboardHealthStatusItem item,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} $_kComingSoonSuffix'),
      ),
    );
  }
}
