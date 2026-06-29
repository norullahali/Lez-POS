import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/core/widgets/report_async_body.dart';
import '../../models/cash_ledger_event.dart';
import '../../providers/dashboard_providers.dart';
import '../../widgets/cash_ledger_event_drill_down.dart';
import 'dashboard_recent_activity_row.dart';

/// Recent Activity section -- watches [dashboardRecentActivityProvider] only.
class DashboardRecentActivitySection extends ConsumerWidget {
  const DashboardRecentActivitySection({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  static const _sectionTitleStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );
  static const _sectionSubtitleStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 13,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(dashboardRecentActivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '\u0622\u062e\u0631 \u0627\u0644\u062d\u0631\u0643\u0627\u062a',
          style: _sectionTitleStyle,
        ),
        const SizedBox(height: 2),
        const Text(
          '\u0622\u062e\u0631 \u0627\u0644\u0639\u0645\u0644\u064a\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629 \u0627\u0644\u0645\u0633\u062c\u0644\u0629',
          style: _sectionSubtitleStyle,
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ReportAsyncBody<List<CashLedgerEvent>>(
            asyncValue: activityAsync,
            onRetry: onRefresh,
            loadingStyle: ReportLoadingStyle.spinner,
            emptyIcon: Icons.account_balance_wallet_outlined,
            emptyMessage:
                '\u0644\u0627 \u062a\u0648\u062c\u062f \u062d\u0631\u0643\u0627\u062a \u0641\u064a \u0627\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629',
            isEmpty: (entries) => entries.isEmpty,
            dataBuilder: (_, entries) => _RecentActivityList(
              entries: entries,
              onEventTap: (event) =>
                  CashLedgerEventDrillDown.open(context, ref, event),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList({
    required this.entries,
    required this.onEventTap,
  });

  final List<CashLedgerEvent> entries;
  final void Function(CashLedgerEvent event) onEventTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          DashboardRecentActivityRow(
            event: entries[i],
            onTap: () => onEventTap(entries[i]),
          ),
        ],
      ],
    );
  }
}