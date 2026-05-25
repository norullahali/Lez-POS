import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../providers/operations_providers.dart';
import '../widgets/expiry_dashboard_card.dart';
import '../widgets/insight_feed_tile.dart';
import '../widgets/notification_bell.dart';
import '../widgets/operational_alert_card.dart';
import '../widgets/operational_health_card.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends ConsumerState<NotificationCenterScreen>
    with SingleTickerProviderStateMixin {
  OperationalAlertSeverity? _severityFilter;
  OperationalAlertType? _typeFilter;
  bool _showDismissed = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<OperationalAlert> _filter(List<OperationalAlert> alerts) {
    return alerts.where((a) {
      if (!_showDismissed && (!a.state.isVisibleInInbox || a.isDismissed)) return false;
      if (_severityFilter != null && a.severity != _severityFilter) return false;
      if (_typeFilter != null && a.type != _typeFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(operationalAlertsProvider);
    final insightsAsync = ref.watch(operationalInsightsProvider);
    final closingAsync = ref.watch(dailyClosingSummaryProvider);
    final reportsAsync = ref.watch(scheduledReportsConfigProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'التنبيهات'),
                    Tab(text: 'رؤى'),
                    Tab(text: 'الإغلاق'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: () => ref.read(operationalAlertsProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _alertsTab(alertsAsync),
              insightsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => InsightFeedTile(insight: items[i]),
                ),
              ),
              closingAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (summary) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'ملخص إغلاق ${summary.date.toString().split(' ').first}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ...summary.insightLines.map(
                      (line) => ListTile(
                        leading: const Icon(Icons.check_circle_outline, color: AppColors.success),
                        title: Text(line),
                      ),
                    ),
                    const Divider(),
                    const OperationalHealthCard(),
                    const ExpiryDashboardCard(),
                    reportsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (configs) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'التقارير المجدولة',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          ...configs.map(
                            (c) => ListTile(
                              title: Text(c.titleAr),
                              subtitle: Text(
                                c.lastGeneratedAt != null
                                    ? 'آخر توليد: ${c.lastGeneratedAt}'
                                    : 'لم يُولَّد بعد',
                              ),
                              trailing: Switch(
                                value: c.enabled,
                                onChanged: (v) async {
                                  final svc = ref.read(scheduledReportsServiceProvider);
                                  final list = await svc.loadConfigs();
                                  final idx = list.indexWhere((x) => x.id == c.id);
                                  if (idx >= 0) {
                                    list[idx] = c.copyWith(enabled: v);
                                    await svc.saveConfigs(list);
                                    ref.invalidate(scheduledReportsConfigProvider);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _alertsTab(AsyncValue<List<OperationalAlert>> alertsAsync) {
    return alertsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e')),
      data: (alerts) {
        final filtered = _filter(alerts);
        final grouped = <OperationalAlertSeverity, List<OperationalAlert>>{};
        for (final a in filtered) {
          grouped.putIfAbsent(a.severity, () => []).add(a);
        }

        return Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('الكل'),
                    selected: _severityFilter == null && _typeFilter == null,
                    onSelected: (_) => setState(() {
                      _severityFilter = null;
                      _typeFilter = null;
                    }),
                  ),
                  const SizedBox(width: 6),
                  ...OperationalAlertSeverity.values.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FilterChip(
                        label: Text(severityLabel(s)),
                        selected: _severityFilter == s,
                        onSelected: (_) => setState(() => _severityFilter = s),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('المؤرشف'),
                    selected: _showDismissed,
                    onSelected: (v) => setState(() => _showDismissed = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد تنبيهات',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textHint),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final severity in OperationalAlertSeverity.values)
                          if (grouped[severity]?.isNotEmpty ?? false) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text(
                                severityLabel(severity),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            ...grouped[severity]!.map(
                              (a) => OperationalAlertCard(
                                alert: a,
                                onDismiss: () => ref
                                    .read(operationalAlertsProvider.notifier)
                                    .dismiss(a.fingerprint),
                                onAcknowledge: () => ref
                                    .read(operationalAlertsProvider.notifier)
                                    .acknowledge(a.fingerprint),
                                onResolve: () => ref
                                    .read(operationalAlertsProvider.notifier)
                                    .resolve(a.fingerprint),
                              ),
                            ),
                          ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
