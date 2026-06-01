// lib/features/returns/utils/return_analytics_date_utils.dart
//
// Single source of truth for Return Analytics date normalization.
import '../models/return_analytics_models.dart';

class ReturnAnalyticsDateUtils {
  ReturnAnalyticsDateUtils._();

  static DateTime startOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static int startMs(DateTime d) => startOfDay(d).millisecondsSinceEpoch;

  static int endMs(DateTime d) => endOfDay(d).millisecondsSinceEpoch;

  static int get todayStartMs => startMs(DateTime.now());

  static int get weekStartMs {
    final now = DateTime.now();
    final daysBack = now.weekday - 1;
    return startMs(now.subtract(Duration(days: daysBack)));
  }

  static int get monthStartMs =>
      startMs(DateTime(DateTime.now().year, DateTime.now().month, 1));

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

  static int readTimestampMs(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is num) return value.toInt();
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    }
    return 0;
  }
}