import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/filters/report_filter_provider.dart';
import '../../core/models/report_tab_id.dart';
import '../../core/providers/report_permissions.dart';
import '../../core/services/report_query_cache.dart';
import '../../core/widgets/report_async_body.dart';
import '../../core/widgets/report_filter_bar.dart';

export 'analytics_filter_utils.dart';

typedef AnalyticsDataBuilder<T> = Widget Function(BuildContext context, T data);

class AnalyticsModuleScaffold<T> extends ConsumerWidget {
  const AnalyticsModuleScaffold({
    super.key,
    required this.tabId,
    required this.asyncValue,
    required this.onRetry,
    required this.builder,
    this.loadingStyle = ReportLoadingStyle.skeletonMetrics,
    this.emptyMessage,
    this.isEmpty,
    this.onExport,
    this.showExport = true,
    this.filterMode = ReportFilterBarMode.dateRange,
  });

  final ReportTabId tabId;
  final AsyncValue<T> asyncValue;
  final VoidCallback onRetry;
  final AnalyticsDataBuilder<T> builder;
  final ReportLoadingStyle loadingStyle;
  final String? emptyMessage;
  final bool Function(T data)? isEmpty;
  final VoidCallback? onExport;
  final bool showExport;
  final ReportFilterBarMode filterMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.reportFilter(tabId);
    final canExport = ref.watch(canExportReportsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Material(
            elevation: 0,
            color: Colors.white,
            child: ReportFilterBar(
              mode: filterMode,
              filter: filter,
              showExport: showExport,
              onFilterChanged: (f) => ref.updateReportFilter(tabId, f, debounce: true),
              onRefresh: () {
                ReportQueryCache.invalidatePrefix(tabId.cachePrefix);
                onRetry();
              },
              onExport: canExport ? onExport : null,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ReportAsyncBody<T>(
              asyncValue: asyncValue,
              loadingStyle: loadingStyle,
              onRetry: onRetry,
              emptyMessage: emptyMessage ?? 'لا توجد بيانات للفترة المحددة',
              isEmpty: isEmpty,
              dataBuilder: (context, data) => KeyedSubtree(
                key: PageStorageKey<String>('analytics_scroll_${tabId.name}'),
                child: builder(context, data),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
