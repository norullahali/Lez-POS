import 'cash_ledger_event.dart';
import 'cash_ledger_event_type.dart';
import 'dashboard_filter.dart';

/// Composite analytics payload for Financial Dashboard charts (Phase 5.3).
///
/// Immutable pure-data container. Aggregations live in
/// [FinancialLedgerRepository]; formatting lives in UI (Phase 5.3.2+).
class FinancialDashboardCashAnalytics {
  const FinancialDashboardCashAnalytics({
    required this.timeSeries,
    required this.breakdown,
  });

  final FinancialDashboardCashFlowTimeSeries timeSeries;
  final FinancialDashboardCashFlowBreakdown breakdown;

  static const empty = FinancialDashboardCashAnalytics(
    timeSeries: FinancialDashboardCashFlowTimeSeries.empty,
    breakdown: FinancialDashboardCashFlowBreakdown.empty,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardCashAnalytics &&
          runtimeType == other.runtimeType &&
          timeSeries == other.timeSeries &&
          breakdown == other.breakdown;

  @override
  int get hashCode => Object.hash(timeSeries, breakdown);

  FinancialDashboardCashAnalytics copyWith({
    FinancialDashboardCashFlowTimeSeries? timeSeries,
    FinancialDashboardCashFlowBreakdown? breakdown,
  }) =>
      FinancialDashboardCashAnalytics(
        timeSeries: timeSeries ?? this.timeSeries,
        breakdown: breakdown ?? this.breakdown,
      );
}

/// Bucketed inflow/outflow over time for the selected filter period.
///
/// [granularity] records the bucket size used when the series was built.
/// [buckets] includes gap-filled zero buckets for the full filter range.
class FinancialDashboardCashFlowTimeSeries {
  const FinancialDashboardCashFlowTimeSeries({
    required this.granularity,
    required this.buckets,
  });

  final DashboardGranularity granularity;
  final List<FinancialDashboardTimeSeriesBucket> buckets;

  static const empty = FinancialDashboardCashFlowTimeSeries(
    granularity: DashboardGranularity.day,
    buckets: [],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardCashFlowTimeSeries &&
          runtimeType == other.runtimeType &&
          granularity == other.granularity &&
          _listEquals(buckets, other.buckets);

  @override
  int get hashCode => Object.hash(granularity, Object.hashAll(buckets));

  FinancialDashboardCashFlowTimeSeries copyWith({
    DashboardGranularity? granularity,
    List<FinancialDashboardTimeSeriesBucket>? buckets,
  }) =>
      FinancialDashboardCashFlowTimeSeries(
        granularity: granularity ?? this.granularity,
        buckets: buckets ?? this.buckets,
      );
}

/// One temporal bucket in a cash-flow trend series.
class FinancialDashboardTimeSeriesBucket {
  const FinancialDashboardTimeSeriesBucket({
    required this.label,
    required this.inflow,
    required this.outflow,
  });

  /// Stable bucket key for UI formatting (Phase 5.3.2).
  ///
  /// Formats: `YYYY-MM-DD` (day), `week:N` (week index from range start),
  /// `YYYY-MM` (month). Not display-ready — chart mapper applies locale.
  final String label;
  final double inflow;
  final double outflow;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardTimeSeriesBucket &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          inflow == other.inflow &&
          outflow == other.outflow;

  @override
  int get hashCode => Object.hash(label, inflow, outflow);

  FinancialDashboardTimeSeriesBucket copyWith({
    String? label,
    double? inflow,
    double? outflow,
  }) =>
      FinancialDashboardTimeSeriesBucket(
        label: label ?? this.label,
        inflow: inflow ?? this.inflow,
        outflow: outflow ?? this.outflow,
      );
}

/// Cash movement grouped by ledger event type for the selected filter period.
class FinancialDashboardCashFlowBreakdown {
  const FinancialDashboardCashFlowBreakdown({
    required this.slices,
  });

  final List<FinancialDashboardBreakdownSlice> slices;

  static const empty = FinancialDashboardCashFlowBreakdown(slices: []);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardCashFlowBreakdown &&
          runtimeType == other.runtimeType &&
          _listEquals(slices, other.slices);

  @override
  int get hashCode => Object.hashAll(slices);

  FinancialDashboardCashFlowBreakdown copyWith({
    List<FinancialDashboardBreakdownSlice>? slices,
  }) =>
      FinancialDashboardCashFlowBreakdown(
        slices: slices ?? this.slices,
      );
}

/// One composition slice for a single [CashLedgerEventType].
class FinancialDashboardBreakdownSlice {
  const FinancialDashboardBreakdownSlice({
    required this.eventType,
    required this.amount,
    required this.direction,
  });

  final CashLedgerEventType eventType;
  final double amount;
  final CashLedgerDirection direction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardBreakdownSlice &&
          runtimeType == other.runtimeType &&
          eventType == other.eventType &&
          amount == other.amount &&
          direction == other.direction;

  @override
  int get hashCode => Object.hash(eventType, amount, direction);

  FinancialDashboardBreakdownSlice copyWith({
    CashLedgerEventType? eventType,
    double? amount,
    CashLedgerDirection? direction,
  }) =>
      FinancialDashboardBreakdownSlice(
        eventType: eventType ?? this.eventType,
        amount: amount ?? this.amount,
        direction: direction ?? this.direction,
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}