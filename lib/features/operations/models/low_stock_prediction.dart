enum ReorderUrgency { safe, warning, urgent, critical }

class LowStockPrediction {
  const LowStockPrediction({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.dailySalesRate,
    required this.daysRemaining,
    required this.urgency,
  });

  final int productId;
  final String productName;
  final double currentStock;
  final double dailySalesRate;
  final double daysRemaining;
  final ReorderUrgency urgency;
}
