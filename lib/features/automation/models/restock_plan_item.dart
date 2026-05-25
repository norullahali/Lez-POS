enum RestockPressure { low, medium, high, critical }

class RestockPlanItem {
  const RestockPlanItem({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.targetStock,
    required this.pressure,
    required this.scheduleHintAr,
    required this.explanation,
  });
  final int productId;
  final String productName;
  final double currentStock;
  final double targetStock;
  final RestockPressure pressure;
  final String scheduleHintAr;
  final String explanation;
}