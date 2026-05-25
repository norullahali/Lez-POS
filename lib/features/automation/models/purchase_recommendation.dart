class PurchaseRecommendationLine {
  const PurchaseRecommendationLine({
    required this.productId,
    required this.productName,
    required this.suggestedQty,
    required this.unitCost,
    required this.explanation,
  });
  final int productId;
  final String productName;
  final double suggestedQty;
  final double unitCost;
  final String explanation;
  double get estimatedCost => suggestedQty * unitCost;
}

class SupplierPurchaseRecommendation {
  const SupplierPurchaseRecommendation({
    required this.supplierId,
    required this.supplierName,
    required this.lines,
    required this.projectedCoverageDays,
  });
  final int? supplierId;
  final String supplierName;
  final List<PurchaseRecommendationLine> lines;
  final double projectedCoverageDays;
  double get estimatedTotal => lines.fold(0.0, (s, l) => s + l.estimatedCost);
}