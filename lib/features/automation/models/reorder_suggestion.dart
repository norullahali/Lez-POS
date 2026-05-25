enum ReorderUrgency { safe, warning, urgent, critical }

class ReorderSuggestion {
  const ReorderSuggestion({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.suggestedQty,
    required this.urgency,
    required this.daysRemaining,
    required this.dailyRate,
    required this.explanation,
    this.supplierId,
    this.supplierName,
    this.priorityScore = 0,
  });

  final int productId;
  final String productName;
  final double currentStock;
  final double suggestedQty;
  final ReorderUrgency urgency;
  final double daysRemaining;
  final double dailyRate;
  final String explanation;
  final int? supplierId;
  final String? supplierName;
  final int priorityScore;
}