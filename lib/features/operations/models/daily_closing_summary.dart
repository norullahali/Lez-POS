class DailyClosingSummary {
  const DailyClosingSummary({
    required this.date,
    required this.totalSales,
    required this.invoiceCount,
    required this.totalReturns,
    required this.returnRatePercent,
    required this.inventoryAlerts,
    required this.debtReceivable,
    required this.debtPayable,
    required this.topProductName,
    required this.weakCategoryName,
    required this.topCashierName,
    required this.sessionMismatchCount,
    required this.insightLines,
  });

  final DateTime date;
  final double totalSales;
  final int invoiceCount;
  final double totalReturns;
  final double returnRatePercent;
  final int inventoryAlerts;
  final double debtReceivable;
  final double debtPayable;
  final String? topProductName;
  final String? weakCategoryName;
  final String? topCashierName;
  final int sessionMismatchCount;
  final List<String> insightLines;
}
