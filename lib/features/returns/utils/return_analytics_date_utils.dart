// lib/features/returns/utils/return_analytics_date_utils.dart
//
// Single source of truth for Return Analytics date normalization.
// return_audit_logs.created_at is stored as Unix epoch SECONDS (10-digit ints).
import '../models/return_analytics_models.dart';

class ReturnAnalyticsDateUtils {
  ReturnAnalyticsDateUtils._();

  /// Values below this are epoch seconds; at/above are epoch milliseconds.
  static const int epochMsThreshold = 100000000000;

  static DateTime startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// Inclusive lower bound in epoch milliseconds (calendar helpers).
  static int startMs(DateTime d) => startOfDay(d).millisecondsSinceEpoch;

  /// Inclusive upper bound in epoch milliseconds (calendar helpers).
  static int endMs(DateTime d) => endOfDay(d).millisecondsSinceEpoch;

  /// SQL bind values for return_audit_logs.created_at (epoch seconds).
  static int startSec(DateTime d) => startMs(d) ~/ 1000;

  static int endSec(DateTime d) => endMs(d) ~/ 1000;

  static int get todayStartSec => startSec(DateTime.now());

  static int get weekStartSec {
    final now = DateTime.now();
    final daysBack = now.weekday - 1;
    return startSec(now.subtract(Duration(days: daysBack)));
  }

  static int get monthStartSec =>
      startSec(DateTime(DateTime.now().year, DateTime.now().month, 1));

  static ReturnAnalyticsFilter normalizeFilter(ReturnAnalyticsFilter raw) {
    return ReturnAnalyticsFilter(
      fromDate: raw.fromDate == null ? null : startOfDay(raw.fromDate!),
      toDate: raw.toDate == null ? null : startOfDay(raw.toDate!),
      cashierUserId: raw.cashierUserId,
      returnType: raw.returnType,
      productId: raw.productId,
    );
  }

  static String filterCacheKey(ReturnAnalyticsFilter f) {
    final from = f.fromDate?.millisecondsSinceEpoch ?? 'all';
    final to = f.toDate?.millisecondsSinceEpoch ?? 'all';
    final type = f.returnType ?? 'all';
    final cashier = f.cashierUserId?.toString() ?? 'all';
    final product = f.productId?.toString() ?? 'all';
    return '${from}_${to}_${type}_${cashier}_$product';
  }

  /// Parses return_audit_logs.created_at (seconds or ms) to local DateTime.
  static DateTime parseTimestamp(Object? value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    if (value is String) return DateTime.parse(value).toLocal();
    if (value is num) {
      final v = value.toInt();
      if (v.abs() < epochMsThreshold) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
            .toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }
    return DateTime.now();
  }
}
