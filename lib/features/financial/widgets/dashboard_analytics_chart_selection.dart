/// Presentation-only chart selection for Financial Dashboard analytics (Phase 5.3.3.1).
///
/// Stores chart indices only -- not a copy of analytics data. Not persisted.
/// At most one selection is active (trend bucket XOR composition slice).
///
/// Index semantics:
/// - [DashboardTrendBucketSelection.bucketIndex] matches the cached trend
///   [ReportChartConfig] point order (same index as [FinancialDashboardTimeSeriesBucket]).
/// - [DashboardCompositionSliceSelection.sliceIndex] matches the positive-slice
///   pie point list from [FinancialDashboardChartMapper.toCashFlowCompositionChart].
sealed class DashboardAnalyticsChartSelection {
  const DashboardAnalyticsChartSelection();
}

/// Selected time bucket in the cash-flow trend chart.
class DashboardTrendBucketSelection extends DashboardAnalyticsChartSelection {
  const DashboardTrendBucketSelection({required this.bucketIndex});

  final int bucketIndex;
}

/// Selected slice in the cash-flow composition pie chart.
class DashboardCompositionSliceSelection extends DashboardAnalyticsChartSelection {
  const DashboardCompositionSliceSelection({required this.sliceIndex});

  final int sliceIndex;
}