import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../reports/modules/shared/analytics_formatters.dart';
import '../models/financial_dashboard_cash_analytics.dart';
import 'dashboard_analytics_chart_selection.dart';
import 'financial_dashboard_chart_mapper.dart';

/// Read-only UX feedback for the active analytics chart selection.
///
/// Displays values from resolved [FinancialDashboardCashAnalytics] at the
/// selected index. No navigation, provider invalidation, or drill-down
/// (aggregate charts lack per-event IDs — Phase 5.3.3.2+).
class DashboardAnalyticsSelectionFeedback extends StatelessWidget {
  const DashboardAnalyticsSelectionFeedback({
    super.key,
    required this.analytics,
    required this.selection,
    required this.onClear,
  });

  final FinancialDashboardCashAnalytics analytics;
  final DashboardAnalyticsChartSelection selection;
  final VoidCallback onClear;

  static const _labelStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 12,
  );
  static const _valueStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    return switch (selection) {
      DashboardTrendBucketSelection(:final bucketIndex) =>
        _buildTrendFeedback(context, bucketIndex),
      DashboardCompositionSliceSelection(:final sliceIndex) =>
        _buildCompositionFeedback(context, sliceIndex),
    };
  }

  Widget _buildTrendFeedback(BuildContext context, int bucketIndex) {
    final buckets = analytics.timeSeries.buckets;
    if (bucketIndex < 0 || bucketIndex >= buckets.length) {
      return const SizedBox.shrink();
    }
    final bucket = buckets[bucketIndex];
    final label = FinancialDashboardChartMapper.formatBucketLabelForDisplay(
      bucket.label,
      analytics.timeSeries.granularity,
      bucketCount: buckets.length,
      allRawLabels: buckets.map((b) => b.label),
    );

    return _SelectionCard(
      title: '\u0627\u0644\u0641\u062a\u0631\u0629 \u0627\u0644\u0645\u062d\u062f\u062f\u0629: $label',
      onClear: onClear,
      children: [
        _FeedbackRow(
          label: '\u0625\u064a\u0631\u0627\u062f \u0646\u0642\u062f\u064a',
          value: AnalyticsFormatters.money(bucket.inflow),
          color: AppColors.success,
        ),
        _FeedbackRow(
          label: '\u0635\u0631\u0641 \u0646\u0642\u062f\u064a',
          value: AnalyticsFormatters.money(bucket.outflow),
          color: AppColors.error,
        ),
      ],
    );
  }

  Widget _buildCompositionFeedback(BuildContext context, int sliceIndex) {
    final positiveSlices = analytics.breakdown.slices
        .where((s) => s.amount > 0)
        .toList(growable: false);
    if (sliceIndex < 0 || sliceIndex >= positiveSlices.length) {
      return const SizedBox.shrink();
    }
    final slice = positiveSlices[sliceIndex];

    return _SelectionCard(
      title: '\u0628\u0646\u062f \u0645\u062d\u062f\u062f: ${slice.eventType.labelAr}',
      onClear: onClear,
      children: [
        _FeedbackRow(
          label: '\u0627\u0644\u0645\u0628\u0644\u063a',
          value: AnalyticsFormatters.money(slice.amount),
          color: AppColors.primary,
        ),
      ],
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.title,
    required this.onClear,
    required this.children,
  });

  final String title;
  final VoidCallback onClear;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.touch_app_rounded, size: 16, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: DashboardAnalyticsSelectionFeedback._valueStyle),
                ),
                IconButton(
                  tooltip: '\u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u062a\u062d\u062f\u064a\u062f',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.textSecondary,
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _FeedbackRow extends StatelessWidget {
  const _FeedbackRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: DashboardAnalyticsSelectionFeedback._labelStyle),
          const Spacer(),
          Text(value, style: DashboardAnalyticsSelectionFeedback._valueStyle),
        ],
      ),
    );
  }
}