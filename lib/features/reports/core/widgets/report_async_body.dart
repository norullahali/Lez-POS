import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'report_empty_view.dart';
import 'report_error_view.dart';
import 'report_loading_view.dart';
import 'report_skeleton_view.dart';

typedef ReportDataBuilder<T> = Widget Function(BuildContext context, T data);

enum ReportLoadingStyle { spinner, skeletonMetrics, skeletonChart, skeletonTable }

class ReportAsyncBody<T> extends StatelessWidget {
  const ReportAsyncBody({
    super.key,
    required this.asyncValue,
    required this.dataBuilder,
    this.loadingMessage,
    this.loadingStyle = ReportLoadingStyle.spinner,
    this.emptyIcon = Icons.bar_chart_rounded,
    this.emptyMessage = 'لا توجد بيانات',
    this.isEmpty,
    this.onRetry,
    this.keepPreviousData = true,
  });

  final AsyncValue<T> asyncValue;
  final ReportDataBuilder<T> dataBuilder;
  final String? loadingMessage;
  final ReportLoadingStyle loadingStyle;
  final IconData emptyIcon;
  final String emptyMessage;
  final bool Function(T data)? isEmpty;
  final VoidCallback? onRetry;
  final bool keepPreviousData;

  @override
  Widget build(BuildContext context) {
    if (keepPreviousData && asyncValue.isLoading && asyncValue.hasValue) {
      return Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Opacity(
              opacity: 0.55,
              child: _buildData(context, asyncValue.requireValue),
            ),
          ),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
      );
    }

    return asyncValue.when(
      loading: () => _loadingWidget(),
      error: (e, _) => ReportErrorView(message: 'خطأ: $e', onRetry: onRetry),
      data: (data) => _buildData(context, data),
    );
  }

  Widget _buildData(BuildContext context, T data) {
    if (isEmpty != null && isEmpty!(data)) {
      return ReportEmptyView(icon: emptyIcon, message: emptyMessage);
    }
    return dataBuilder(context, data);
  }

  Widget _loadingWidget() {
    return switch (loadingStyle) {
      ReportLoadingStyle.skeletonMetrics => const ReportMetricSkeletonGrid(),
      ReportLoadingStyle.skeletonChart => const ReportChartSkeleton(),
      ReportLoadingStyle.skeletonTable => const ReportTableSkeleton(),
      ReportLoadingStyle.spinner => ReportLoadingView(
          message: loadingMessage ?? 'جاري تحميل التقرير...',
        ),
    };
  }
}
