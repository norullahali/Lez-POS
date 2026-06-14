import '../../returns/utils/return_analytics_date_utils.dart';

/// Normalizes ledger event timestamps from mixed SQL UNION sources.
class CashLedgerDateUtils {
  CashLedgerDateUtils._();

  /// Handles epoch seconds (return_audit_logs), ms integers, ISO strings,
  /// and DateTime values mis-read when seconds were stored as milliseconds.
  static DateTime parseEventTimestamp(Object? value) {
    if (value is DateTime) {
      final local = value.isUtc ? value.toLocal() : value;
      final ms = value.millisecondsSinceEpoch;
      if (local.year < 1980 &&
          ms > 0 &&
          ms.abs() < ReturnAnalyticsDateUtils.epochMsThreshold) {
        return DateTime.fromMillisecondsSinceEpoch(ms * 1000, isUtc: true)
            .toLocal();
      }
      return local;
    }
    return ReturnAnalyticsDateUtils.parseTimestamp(value);
  }
}