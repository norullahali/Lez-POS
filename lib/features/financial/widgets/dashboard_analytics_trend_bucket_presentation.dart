import 'package:flutter/material.dart';

import '../models/dashboard_filter.dart';
import '../models/financial_dashboard_cash_analytics.dart';

/// Presentation-only drill-down span for one displayed trend chart bucket.
///
/// **Ownership:** built and cached by [_AnalyticsChartCardsState] — not part of
/// [FinancialDashboardCashFlowTimeSeries] or any provider payload.
///
/// **Immutability:** const constructor; all fields are final; safe to cache
/// by reference across rebuilds.
///
/// **Lifecycle:** regenerated in `_syncBaseConfigs()` when analytics or dashboard
/// filter changes; never mutated after creation.
///
/// Not business data — never stored in repository or analytics providers.
class DashboardTrendBucketPresentationMeta {
  const DashboardTrendBucketPresentationMeta({
    required this.bucketStart,
    required this.bucketEnd,
    required this.displaySpan,
    required this.sourceLabelIndexes,
    required this.isMerged,
  });

  /// Inclusive calendar start of the represented period.
  final DateTime bucketStart;

  /// Inclusive calendar end of the represented period.
  final DateTime bucketEnd;

  /// Human-readable span for presentation (not used in ledger queries).
  final String displaySpan;

  /// Indexes into the pre-merge label timeline aligned with repository gap-fill.
  final List<int> sourceLabelIndexes;

  /// True when [sourceLabelIndexes] spans more than one pre-merge label.
  final bool isMerged;

  /// Inclusive calendar range consumed by trend drill-down navigation.
  ///
  /// Precomputed at metadata build time — drill-down reads this only; no label
  /// parsing at navigation time.
  DateTimeRange get drillDownRange =>
      DateTimeRange(start: bucketStart, end: bucketEnd);
}

/// Builds trend bucket presentation metadata parallel to chart bucket indices.
///
/// **Merge semantics:** when the label timeline exceeds repository chart caps,
/// labels are chunked identically to [FinancialLedgerRepository] aggregation.
/// Each merged meta spans first→last label calendar bounds in the chunk.
///
/// **Fail-closed:** returns `[]` when meta count ≠ bucket count so trend
/// drill-down is disabled rather than navigating with a wrong span.
///
/// Mirrors repository merge caps and label generation for display alignment only.
/// Does not read SQL, providers, or mutate analytics models.
class DashboardAnalyticsTrendBucketPresentation {
  DashboardAnalyticsTrendBucketPresentation._();

  // Must stay aligned with FinancialLedgerRepository private chart caps.
  static const _maxDailyBuckets = 31;
  static const _maxWeeklyBuckets = 26;
  static const _maxMonthlyBuckets = 12;

  /// One entry per [FinancialDashboardCashFlowTimeSeries.buckets] index.
  ///
  /// Call once per analytics payload (same cadence as chart config cache).
  static List<DashboardTrendBucketPresentationMeta> forTimeSeries({
    required FinancialDashboardCashFlowTimeSeries timeSeries,
    required DateTimeRange dashboardRange,
  }) {
    final buckets = timeSeries.buckets;
    if (buckets.isEmpty) return const [];

    final granularity = timeSeries.granularity;
    final rangeStart = _startOfDay(dashboardRange.start);
    final rangeEndInclusive = _startOfDay(dashboardRange.end);
    final endExclusive = _endExclusive(rangeEndInclusive);

    final allLabels =
        _generateBucketLabels(rangeStart, endExclusive, granularity);
    if (allLabels.isEmpty) return const [];

    final maxBuckets = _maxBucketsFor(granularity);
    final metas = allLabels.length <= maxBuckets
        ? _metasForUnmergedLabels(
            allLabels,
            granularity,
            rangeStart,
            rangeEndInclusive,
          )
        : _metasForMergedLabels(
            allLabels,
            granularity,
            rangeStart,
            rangeEndInclusive,
            maxBuckets,
          );

    // Fail-closed: length mismatch means presentation cannot align with chart.
    if (metas.length != buckets.length) return const [];
    return metas;
  }

  static List<DashboardTrendBucketPresentationMeta> _metasForUnmergedLabels(
    List<String> labels,
    DashboardGranularity granularity,
    DateTime rangeStart,
    DateTime rangeEndInclusive,
  ) {
    return List.generate(labels.length, (index) {
      final span = _dateRangeForLabel(
        labels[index],
        granularity,
        rangeStart,
        rangeEndInclusive,
      );
      if (span == null) return null;
      return DashboardTrendBucketPresentationMeta(
        bucketStart: span.start,
        bucketEnd: span.end,
        displaySpan: _formatDisplaySpan(span),
        sourceLabelIndexes: [index],
        isMerged: false,
      );
    }).whereType<DashboardTrendBucketPresentationMeta>().toList(growable: false);
  }

  /// Merged path: chunk size matches repository cap merge; span is first→last label.
  static List<DashboardTrendBucketPresentationMeta> _metasForMergedLabels(
    List<String> labels,
    DashboardGranularity granularity,
    DateTime rangeStart,
    DateTime rangeEndInclusive,
    int maxBuckets,
  ) {
    final chunkSize = (labels.length + maxBuckets - 1) ~/ maxBuckets;
    final metas = <DashboardTrendBucketPresentationMeta>[];

    for (var i = 0; i < labels.length; i += chunkSize) {
      final chunkEnd = (i + chunkSize).clamp(0, labels.length);
      final chunk = labels.sublist(i, chunkEnd);
      final firstSpan = _dateRangeForLabel(
        chunk.first,
        granularity,
        rangeStart,
        rangeEndInclusive,
      );
      final lastSpan = _dateRangeForLabel(
        chunk.last,
        granularity,
        rangeStart,
        rangeEndInclusive,
      );
      if (firstSpan == null || lastSpan == null) continue;

      metas.add(
        DashboardTrendBucketPresentationMeta(
          bucketStart: firstSpan.start,
          bucketEnd: lastSpan.end,
          displaySpan: _formatDisplaySpan(
            DateTimeRange(start: firstSpan.start, end: lastSpan.end),
          ),
          sourceLabelIndexes: List.generate(chunk.length, (j) => i + j),
          isMerged: chunk.length > 1,
        ),
      );
    }

    return metas;
  }

  static int _maxBucketsFor(DashboardGranularity granularity) =>
      switch (granularity) {
        DashboardGranularity.day => _maxDailyBuckets,
        DashboardGranularity.week => _maxWeeklyBuckets,
        DashboardGranularity.month => _maxMonthlyBuckets,
      };

  static List<String> _generateBucketLabels(
    DateTime start,
    DateTime endExclusive,
    DashboardGranularity granularity,
  ) {
    return switch (granularity) {
      DashboardGranularity.day => _generateDayLabels(start, endExclusive),
      DashboardGranularity.week => _generateWeekLabels(start, endExclusive),
      DashboardGranularity.month => _generateMonthLabels(start, endExclusive),
    };
  }

  static List<String> _generateDayLabels(
    DateTime start,
    DateTime endExclusive,
  ) {
    final labels = <String>[];
    var cursor = start;
    while (cursor.isBefore(endExclusive)) {
      labels.add(_formatDay(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return labels;
  }

  static List<String> _generateWeekLabels(
    DateTime start,
    DateTime endExclusive,
  ) {
    final labels = <String>[];
    final totalDays = endExclusive.difference(start).inDays;
    if (totalDays <= 0) return labels;
    final weekCount = (totalDays + 6) ~/ 7;
    for (var i = 0; i < weekCount; i++) {
      labels.add('week:$i');
    }
    return labels;
  }

  static List<String> _generateMonthLabels(
    DateTime start,
    DateTime endExclusive,
  ) {
    final labels = <String>[];
    var cursor = DateTime(start.year, start.month);
    while (cursor.isBefore(endExclusive)) {
      labels.add(_formatMonth(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return labels;
  }

  static DateTimeRange? _dateRangeForLabel(
    String label,
    DashboardGranularity granularity,
    DateTime rangeStart,
    DateTime rangeEndInclusive,
  ) {
    switch (granularity) {
      case DashboardGranularity.day:
        final parsed = DateTime.tryParse(label);
        if (parsed == null) return null;
        final day = DateTime(parsed.year, parsed.month, parsed.day);
        if (day.isBefore(rangeStart) || day.isAfter(rangeEndInclusive)) {
          return null;
        }
        return DateTimeRange(start: day, end: day);

      case DashboardGranularity.week:
        if (!label.startsWith('week:')) return null;
        final weekIndex = int.tryParse(label.substring(5));
        if (weekIndex == null || weekIndex < 0) return null;
        final weekStart = rangeStart.add(Duration(days: weekIndex * 7));
        if (weekStart.isAfter(rangeEndInclusive)) return null;
        var weekEnd = weekStart.add(const Duration(days: 6));
        if (weekEnd.isAfter(rangeEndInclusive)) weekEnd = rangeEndInclusive;
        return DateTimeRange(start: weekStart, end: weekEnd);

      case DashboardGranularity.month:
        final parts = label.split('-');
        if (parts.length != 2) return null;
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        if (year == null || month == null || month < 1 || month > 12) {
          return null;
        }
        final monthStart = DateTime(year, month, 1);
        final monthEnd = DateTime(year, month + 1, 0);
        final start =
            monthStart.isBefore(rangeStart) ? rangeStart : monthStart;
        final end =
            monthEnd.isAfter(rangeEndInclusive) ? rangeEndInclusive : monthEnd;
        if (start.isAfter(end)) return null;
        return DateTimeRange(start: start, end: end);
    }
  }

  static String _formatDisplaySpan(DateTimeRange range) {
    if (range.start == range.end) {
      return _formatDay(range.start);
    }
    return '${_formatDay(range.start)} -- ${_formatDay(range.end)}';
  }

  static String _formatDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatMonth(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endExclusive(DateTime d) =>
      _startOfDay(d).add(const Duration(days: 1));
}
