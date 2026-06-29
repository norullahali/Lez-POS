import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../reports/modules/shared/analytics_permission_gate.dart';
import '../providers/dashboard_filter_provider.dart';
import '../providers/dashboard_providers.dart';
import 'widgets/dashboard_cash_flow_section.dart';
import 'widgets/dashboard_filter_section.dart';
import 'widgets/dashboard_recent_activity_section.dart';
import 'widgets/dashboard_supplementary_kpi_section.dart';

/// Financial Dashboard -- read-only KPIs, filter, cash flow, and recent activity.
class FinancialDashboardScreen extends ConsumerStatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  ConsumerState<FinancialDashboardScreen> createState() =>
      _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState
    extends ConsumerState<FinancialDashboardScreen> {
  static const _sectionSpacing = SizedBox(height: 16);

  Future<void> _refresh() async {
    ref.invalidate(dashboardCashFlowProvider);
    ref.invalidate(dashboardCurrentStateProvider);
    ref.invalidate(dashboardRecentActivityProvider);
  }

  void _onResetFilter() {
    final previous = ref.read(dashboardFilterProvider);
    ref.read(dashboardFilterProvider.notifier).reset();
    if (previous == ref.read(dashboardFilterProvider)) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnalyticsPermissionGate(
      requiresFinancial: true,
      requiresInventory: false,
      requiresExecutive: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              _sectionSpacing,
              DashboardFilterSection(
                onRefresh: _refresh,
                onReset: _onResetFilter,
              ),
              _sectionSpacing,
              DashboardCashFlowSection(onRefresh: _refresh),
              _sectionSpacing,
              DashboardSupplementaryKpiSection(onRefresh: _refresh),
              _sectionSpacing,
              DashboardRecentActivitySection(onRefresh: _refresh),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
        );
    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        );

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.insights_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '\u0644\u0648\u062d\u0629 \u0627\u0644\u0645\u0624\u0634\u0631\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              const SizedBox(height: 2),
              Text(
                '\u0645\u0644\u062e\u0635 \u0645\u0627\u0644\u064a \u0644\u062d\u0627\u0644\u0629 \u0627\u0644\u0646\u0634\u0627\u0637 \u0627\u0644\u062a\u062c\u0627\u0631\u064a',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
          ),
        ),
        const _ReadOnlyBadge(),
        IconButton(
          tooltip: '\u062a\u062d\u062f\u064a\u062b',
          icon: const Icon(Icons.refresh_rounded, size: 22),
          color: AppColors.textSecondary,
          onPressed: _refresh,
        ),
      ],
    );
  }
}

class _ReadOnlyBadge extends StatelessWidget {
  const _ReadOnlyBadge();

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(
        Icons.lock_outline,
        size: 16,
        color: AppColors.info,
      ),
      label: const Text('READ ONLY'),
      backgroundColor: AppColors.info.withValues(alpha: 0.08),
    );
  }
}