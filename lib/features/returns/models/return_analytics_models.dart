// lib/features/returns/models/return_analytics_models.dart
//
// Pure data models for the Return Analytics Dashboard.
// All fields are immutable; no business logic here.

class ReturnAnalyticsFilter {
  final DateTime? fromDate;
  final DateTime? toDate;
  final int? cashierUserId;
  final String? returnType; // 'full' | 'partial' | null = all
  final int? productId;

  const ReturnAnalyticsFilter({
    this.fromDate,
    this.toDate,
    this.cashierUserId,
    this.returnType,
    this.productId,
  });

  /// Stable cache key derived from normalized filter dimensions.
  String get cacheKey {
    final from = fromDate?.millisecondsSinceEpoch ?? 'all';
    final to = toDate?.millisecondsSinceEpoch ?? 'all';
    final type = returnType ?? 'all';
    final cashier = cashierUserId?.toString() ?? 'all';
    final product = productId?.toString() ?? 'all';
    return '${from}_${to}_${type}_${cashier}_$product';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReturnAnalyticsFilter &&
          runtimeType == other.runtimeType &&
          fromDate?.millisecondsSinceEpoch ==
              other.fromDate?.millisecondsSinceEpoch &&
          toDate?.millisecondsSinceEpoch ==
              other.toDate?.millisecondsSinceEpoch &&
          cashierUserId == other.cashierUserId &&
          returnType == other.returnType &&
          productId == other.productId;

  @override
  int get hashCode => Object.hash(
        fromDate?.millisecondsSinceEpoch,
        toDate?.millisecondsSinceEpoch,
        cashierUserId,
        returnType,
        productId,
      );

  ReturnAnalyticsFilter copyWith({
    Object? fromDate = _sentinel,
    Object? toDate = _sentinel,
    Object? cashierUserId = _sentinel,
    Object? returnType = _sentinel,
    Object? productId = _sentinel,
  }) {
    return ReturnAnalyticsFilter(
      fromDate: fromDate == _sentinel ? this.fromDate : fromDate as DateTime?,
      toDate: toDate == _sentinel ? this.toDate : toDate as DateTime?,
      cashierUserId: cashierUserId == _sentinel
          ? this.cashierUserId
          : cashierUserId as int?,
      returnType:
          returnType == _sentinel ? this.returnType : returnType as String?,
      productId: productId == _sentinel ? this.productId : productId as int?,
    );
  }

  static const _sentinel = Object();
}

// ---- Overview ---------------------------------------------------------------

class ReturnOverview {
  final int totalCount;
  final double totalAmount;
  final int fullCount;
  final int partialCount;
  final int smartLookupCount;
  final int todayCount;
  final double todayAmount;
  final int weekCount;
  final double weekAmount;
  final int monthCount;
  final double monthAmount;
  final int uniqueProductsReturned;
  final int uniqueCashiers;

  const ReturnOverview({
    required this.totalCount,
    required this.totalAmount,
    required this.fullCount,
    required this.partialCount,
    required this.smartLookupCount,
    required this.todayCount,
    required this.todayAmount,
    required this.weekCount,
    required this.weekAmount,
    required this.monthCount,
    required this.monthAmount,
    required this.uniqueProductsReturned,
    required this.uniqueCashiers,
  });

  static const empty = ReturnOverview(
    totalCount: 0,
    totalAmount: 0,
    fullCount: 0,
    partialCount: 0,
    smartLookupCount: 0,
    todayCount: 0,
    todayAmount: 0,
    weekCount: 0,
    weekAmount: 0,
    monthCount: 0,
    monthAmount: 0,
    uniqueProductsReturned: 0,
    uniqueCashiers: 0,
  );
}

// ---- Filter dropdown options ----------------------------------------------

class AnalyticsFilterOption {
  final int id;
  final String label;

  const AnalyticsFilterOption({required this.id, required this.label});
}

// ---- Daily trend ------------------------------------------------------------

class ReturnTrendPoint {
  final String day; // 'YYYY-MM-DD'
  final int count;
  final double amount;

  const ReturnTrendPoint({
    required this.day,
    required this.count,
    required this.amount,
  });
}

// ---- Top returned products --------------------------------------------------

class TopReturnedProduct {
  final int? productId;
  final String productName;
  final double totalQuantity;
  final double totalAmount;
  final int returnCount;

  const TopReturnedProduct({
    required this.productId,
    required this.productName,
    required this.totalQuantity,
    required this.totalAmount,
    required this.returnCount,
  });
}

// ---- Cashier analytics ------------------------------------------------------

class CashierReturnStat {
  final int? cashierUserId;
  final String cashierName;
  final int totalReturns;
  final double totalAmount;
  final int fullReturns;
  final int partialReturns;

  const CashierReturnStat({
    required this.cashierUserId,
    required this.cashierName,
    required this.totalReturns,
    required this.totalAmount,
    required this.fullReturns,
    required this.partialReturns,
  });
}

// ---- Suspicious indicators --------------------------------------------------

enum SuspiciousSeverity { low, medium, high }

class SuspiciousFlag {
  final String title;
  final String description;
  final SuspiciousSeverity severity;
  final int? relatedUserId;
  final int? relatedProductId;

  const SuspiciousFlag({
    required this.title,
    required this.description,
    required this.severity,
    this.relatedUserId,
    this.relatedProductId,
  });
}

// ---- Recent audit row -------------------------------------------------------

class RecentAuditRow {
  final int id;
  final DateTime createdAt;
  final String returnType;
  final int? invoiceId;
  final String cashierName;
  final String? productName;
  final double returnedQuantity;
  final double returnedAmount;
  final String? returnNote;
  final String? returnReason;

  const RecentAuditRow({
    required this.id,
    required this.createdAt,
    required this.returnType,
    this.invoiceId,
    required this.cashierName,
    this.productName,
    required this.returnedQuantity,
    required this.returnedAmount,
    this.returnNote,
    this.returnReason,
  });
}