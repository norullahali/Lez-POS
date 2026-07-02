import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../reports/modules/shared/analytics_permission_gate.dart';
import '../models/dashboard_export.dart';
import '../models/dashboard_personalization.dart';
import '../providers/dashboard_filter_provider.dart';
import '../providers/dashboard_providers.dart';
import '../services/dashboard_personalization_store.dart';
import 'widgets/dashboard_analytics_section.dart';
import 'widgets/dashboard_cash_flow_section.dart';
import 'widgets/dashboard_filter_section.dart';
import 'widgets/dashboard_alerts_section.dart';
import 'widgets/dashboard_insights_section.dart';
import '../widgets/dashboard_export_builder.dart';
import 'widgets/dashboard_export_controls.dart';
import 'widgets/dashboard_personalization_controls.dart';
import 'widgets/dashboard_personalized_section.dart';
import 'widgets/dashboard_quick_actions_section.dart';
import 'widgets/dashboard_recent_activity_section.dart';
import 'widgets/dashboard_supplementary_kpi_section.dart';

/// Financial Dashboard -- read-only KPIs, filter, cash flow, analytics, and recent activity.
class FinancialDashboardScreen extends ConsumerStatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  ConsumerState<FinancialDashboardScreen> createState() =>
      _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState
    extends ConsumerState<FinancialDashboardScreen> {
  // --- Personalization lifecycle (Phase 5.3.6 / 5.3.9) ---
  // Load once from SharedPreferences on init; save on user change only.
  // Not in Riverpod — presentation preferences stay on this State object.

  /// Presentation preferences loaded from [DashboardPersonalizationStore].
  ///
  /// Updated via [_updatePersonalization] (tune dialog + section collapse).
  DashboardPersonalization _personalization = const DashboardPersonalization();

  /// True after the initial SharedPreferences load completes (no spinner).
  bool _personalizationReady = false;

  /// Last value written to SharedPreferences — screen-level duplicate-save guard.
  DashboardPersonalization? _lastPersistedPersonalization;

  @override
  void initState() {
    super.initState();
    _loadPersonalization();
  }

  /// Loads personalization exactly once per screen instance (Phase 5.3.9).
  Future<void> _loadPersonalization() async {
    final loaded = await DashboardPersonalizationStore.load();
    if (!mounted) return;
    setState(() {
      _personalization = loaded;
      _lastPersistedPersonalization = loaded;
      _personalizationReady = true;
    });
  }

  /// Persists when [value] differs from [_lastPersistedPersonalization].
  ///
  /// Fire-and-forget — UI is not blocked; store performs JSON-level dedup.
  Future<void> _persistPersonalization(DashboardPersonalization value) async {
    if (_lastPersistedPersonalization == value) return;
    _lastPersistedPersonalization = value;
    await DashboardPersonalizationStore.save(value);
  }

  /// Single entry for tune-dialog and collapse changes; saves after setState.
  void _updatePersonalization(DashboardPersonalization next) {
    if (_personalization == next) return;
    setState(() => _personalization = next);
    _persistPersonalization(next);
  }

  Future<void> _refresh() async {
    ref.invalidate(dashboardCashFlowProvider);
    ref.invalidate(dashboardCashAnalyticsProvider);
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

  void _onPersonalizationChanged(DashboardPersonalization next) {
    _updatePersonalization(next);
  }

  void _toggleSectionCollapsed(DashboardSectionId section) {
    _updatePersonalization(_personalization.toggleCollapsed(section));
  }

  /// Builds an export snapshot from already-loaded provider values (Phase 5.3.7).
  ///
  /// **On-demand only:** called when the user opens the export menu — not during
  /// screen build or personalization updates.
  ///
  /// **read vs watch:** uses `ref.read` + `valueOrNull` intentionally — export
  /// must not subscribe to providers or trigger rebuilds; it reads the current
  /// cached async value at menu-open time only.
  ///
  /// Does not invalidate providers or access repositories.
  DashboardExportDocument _prepareExportDocument() {
    return DashboardExportBuilder.build(
      DashboardExportBuildInput(
        filter: ref.read(dashboardFilterProvider),
        personalization: _personalization,
        cashFlow: ref.read(dashboardCashFlowProvider).valueOrNull,
        analytics: ref.read(dashboardCashAnalyticsProvider).valueOrNull,
        currentState: ref.read(dashboardCurrentStateProvider).valueOrNull,
        recentActivity: ref.read(dashboardRecentActivityProvider).valueOrNull,
      ),
    );
  }

  /// Inter-section spacing from [DashboardPersonalization.displayDensity].
  Widget _sectionGap() => SizedBox(height: _personalization.sectionSpacing);

  /// Applies collapse chrome without modifying section widget internals.
  Widget _personalizedSection({
    required DashboardSectionId sectionId,
    required Widget child,
  }) {
    return DashboardPersonalizedSection(
      sectionId: sectionId,
      collapsed: _personalization.isCollapsed(sectionId),
      onToggleCollapse: () => _toggleSectionCollapsed(sectionId),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Blank frame until prefs load — prevents flashing default layout when saved
    // preferences differ. Intentionally no spinner (Phase 5.3.9 foundation).
    if (!_personalizationReady) {
      return const SizedBox.shrink();
    }

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
              _sectionGap(),
              // Phase 5.3.8 — presentation-only quick actions (static catalog,
              // no providers). Fixed placement below header, above filter;
              // not in personalization or export scope.
              const DashboardQuickActionsSection(),
              _sectionGap(),
              DashboardFilterSection(
                onRefresh: _refresh,
                onReset: _onResetFilter,
              ),
              _sectionGap(),
              _personalizedSection(
                sectionId: DashboardSectionId.cashFlow,
                child: DashboardCashFlowSection(onRefresh: _refresh),
              ),
              if (_personalization.showAnalyticsCharts) ...[
                _sectionGap(),
                _personalizedSection(
                  sectionId: DashboardSectionId.analytics,
                  child: DashboardAnalyticsSection(onRefresh: _refresh),
                ),
              ],
              if (_personalization.showInsights) ...[
                _sectionGap(),
                _personalizedSection(
                  sectionId: DashboardSectionId.insights,
                  child: DashboardInsightsSection(onRefresh: _refresh),
                ),
              ],
              if (_personalization.showAlerts) ...[
                _sectionGap(),
                _personalizedSection(
                  sectionId: DashboardSectionId.alerts,
                  child: DashboardAlertsSection(onRefresh: _refresh),
                ),
              ],
              _sectionGap(),
              _personalizedSection(
                sectionId: DashboardSectionId.supplementaryKpi,
                child: DashboardSupplementaryKpiSection(onRefresh: _refresh),
              ),
              if (_personalization.showRecentActivity) ...[
                _sectionGap(),
                _personalizedSection(
                  sectionId: DashboardSectionId.recentActivity,
                  child: DashboardRecentActivitySection(onRefresh: _refresh),
                ),
              ],
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
          tooltip: '\u062a\u062e\u0635\u064a\u0635 \u0627\u0644\u0648\u062d\u0629',
          icon: const Icon(Icons.tune_rounded, size: 22),
          color: AppColors.textSecondary,
          onPressed: () => DashboardPersonalizationControls.show(
            context: context,
            personalization: _personalization,
            onChanged: _onPersonalizationChanged,
          ),
        ),
        DashboardExportButton(onPrepareDocument: _prepareExportDocument),
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
