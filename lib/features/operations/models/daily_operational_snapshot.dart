class DailyOperationalSnapshot {
  const DailyOperationalSnapshot({
    required this.dateKey,
    required this.totalSales,
    required this.invoiceCount,
    required this.totalReturns,
    required this.returnRatePercent,
    required this.inventoryAlertsCount,
    required this.debtReceivable,
    required this.debtPayable,
    required this.sessionMismatchCount,
    required this.suspiciousSignalsCount,
    required this.healthScore,
    required this.capturedAt,
  });

  final String dateKey;
  final double totalSales;
  final int invoiceCount;
  final double totalReturns;
  final double returnRatePercent;
  final int inventoryAlertsCount;
  final double debtReceivable;
  final double debtPayable;
  final int sessionMismatchCount;
  final int suspiciousSignalsCount;
  final int healthScore;
  final DateTime capturedAt;

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'totalSales': totalSales,
        'invoiceCount': invoiceCount,
        'totalReturns': totalReturns,
        'returnRatePercent': returnRatePercent,
        'inventoryAlertsCount': inventoryAlertsCount,
        'debtReceivable': debtReceivable,
        'debtPayable': debtPayable,
        'sessionMismatchCount': sessionMismatchCount,
        'suspiciousSignalsCount': suspiciousSignalsCount,
        'healthScore': healthScore,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory DailyOperationalSnapshot.fromJson(Map<String, dynamic> json) {
    return DailyOperationalSnapshot(
      dateKey: json['dateKey'] as String,
      totalSales: (json['totalSales'] as num).toDouble(),
      invoiceCount: (json['invoiceCount'] as int?) ?? 0,
      totalReturns: (json['totalReturns'] as num).toDouble(),
      returnRatePercent: (json['returnRatePercent'] as num).toDouble(),
      inventoryAlertsCount: (json['inventoryAlertsCount'] as int?) ?? 0,
      debtReceivable: (json['debtReceivable'] as num).toDouble(),
      debtPayable: (json['debtPayable'] as num).toDouble(),
      sessionMismatchCount: (json['sessionMismatchCount'] as int?) ?? 0,
      suspiciousSignalsCount: (json['suspiciousSignalsCount'] as int?) ?? 0,
      healthScore: (json['healthScore'] as int?) ?? 0,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
    );
  }
}
