class AnalyticsTrendPoint {
  const AnalyticsTrendPoint({
    required this.label,
    required this.primary,
    this.secondary,
  });

  final String label;
  final double primary;
  final double? secondary;
}

class ProductProfitRow {
  const ProductProfitRow({
    this.productId,
    required this.name,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.marginPercent,
  });

  final int? productId;
  final String name;
  final double revenue;
  final double cost;
  final double profit;
  final double marginPercent;
}

class ProfitAnalysisData {
  const ProfitAnalysisData({
    required this.grossRevenue,
    required this.estimatedCost,
    required this.grossProfit,
    required this.profitMarginPercent,
    required this.topProfitable,
    required this.lowestMargin,
    required this.trend,
  });

  final double grossRevenue;
  final double estimatedCost;
  final double grossProfit;
  final double profitMarginPercent;
  final List<ProductProfitRow> topProfitable;
  final List<ProductProfitRow> lowestMargin;
  final List<AnalyticsTrendPoint> trend;

  static const empty = ProfitAnalysisData(
    grossRevenue: 0,
    estimatedCost: 0,
    grossProfit: 0,
    profitMarginPercent: 0,
    topProfitable: [],
    lowestMargin: [],
    trend: [],
  );
}

class CashFlowData {
  const CashFlowData({
    required this.cashSales,
    required this.cardSales,
    required this.customerCollections,
    required this.supplierPayments,
    required this.expensesPlaceholder,
    required this.totalInflow,
    required this.totalOutflow,
    required this.netCashFlow,
    required this.timeline,
  });

  final double cashSales;
  final double cardSales;
  final double customerCollections;
  final double supplierPayments;
  final double expensesPlaceholder;
  final double totalInflow;
  final double totalOutflow;
  final double netCashFlow;
  final List<AnalyticsTrendPoint> timeline;

  static const empty = CashFlowData(
    cashSales: 0,
    cardSales: 0,
    customerCollections: 0,
    supplierPayments: 0,
    expensesPlaceholder: 0,
    totalInflow: 0,
    totalOutflow: 0,
    netCashFlow: 0,
    timeline: [],
  );
}

class RankedRow {
  const RankedRow({
    this.id,
    required this.label,
    required this.count,
    required this.amount,
  });

  final int? id;
  final String label;
  final int count;
  final double amount;
}

class LabelCount {
  const LabelCount({required this.label, required this.count});
  final String label;
  final int count;
}

class ReturnImpactData {
  const ReturnImpactData({
    required this.totalReturnedAmount,
    required this.returnRatePercent,
    required this.netRevenueAfterReturns,
    required this.fullReturnCount,
    required this.partialReturnCount,
    required this.topReturnedProducts,
    required this.reasonFrequency,
    required this.trend,
  });

  final double totalReturnedAmount;
  final double returnRatePercent;
  final double netRevenueAfterReturns;
  final int fullReturnCount;
  final int partialReturnCount;
  final List<RankedRow> topReturnedProducts;
  final List<LabelCount> reasonFrequency;
  final List<AnalyticsTrendPoint> trend;

  static const empty = ReturnImpactData(
    totalReturnedAmount: 0,
    returnRatePercent: 0,
    netRevenueAfterReturns: 0,
    fullReturnCount: 0,
    partialReturnCount: 0,
    topReturnedProducts: [],
    reasonFrequency: [],
    trend: [],
  );
}

class LabelAmountPair {
  const LabelAmountPair({required this.label, required this.amount});
  final String label;
  final double amount;
}

class DeadStockRow {
  const DeadStockRow({
    this.productId,
    required this.name,
    required this.stock,
    required this.value,
  });

  final int? productId;
  final String name;
  final double stock;
  final double value;
}

class InventoryMovementData {
  const InventoryMovementData({
    required this.stockIn,
    required this.stockOut,
    required this.returnsIn,
    required this.adjustmentMovement,
    required this.deadInventoryCount,
    required this.turnoverEstimate,
    required this.byType,
    required this.timeline,
    required this.deadStock,
  });

  final double stockIn;
  final double stockOut;
  final double returnsIn;
  final double adjustmentMovement;
  final int deadInventoryCount;
  final double turnoverEstimate;
  final List<LabelAmountPair> byType;
  final List<AnalyticsTrendPoint> timeline;
  final List<DeadStockRow> deadStock;

  static const empty = InventoryMovementData(
    stockIn: 0,
    stockOut: 0,
    returnsIn: 0,
    adjustmentMovement: 0,
    deadInventoryCount: 0,
    turnoverEstimate: 0,
    byType: [],
    timeline: [],
    deadStock: [],
  );
}

class TaxReportData {
  const TaxReportData({
    required this.taxEnabled,
    required this.taxableSales,
    required this.estimatedTaxCollected,
    required this.taxExemptInvoices,
    required this.trend,
  });

  final bool taxEnabled;
  final double taxableSales;
  final double estimatedTaxCollected;
  final int taxExemptInvoices;
  final List<AnalyticsTrendPoint> trend;

  static const empty = TaxReportData(
    taxEnabled: false,
    taxableSales: 0,
    estimatedTaxCollected: 0,
    taxExemptInvoices: 0,
    trend: [],
  );
}

class EmployeePerformanceRow {
  const EmployeePerformanceRow({
    required this.userId,
    required this.name,
    required this.invoiceCount,
    required this.salesAmount,
    required this.averageInvoice,
    required this.returnsHandled,
    required this.refundTotal,
    required this.sessionMinutes,
  });

  final int userId;
  final String name;
  final int invoiceCount;
  final double salesAmount;
  final double averageInvoice;
  final int returnsHandled;
  final double refundTotal;
  final double sessionMinutes;
}

class HourlySalesPoint {
  const HourlySalesPoint({
    required this.hour,
    required this.invoiceCount,
    required this.salesAmount,
  });

  final int hour;
  final int invoiceCount;
  final double salesAmount;
}

class CategoryPerformanceRow {
  const CategoryPerformanceRow({
    this.categoryId,
    required this.name,
    required this.quantitySold,
    required this.revenue,
    required this.profit,
    required this.contributionPercent,
  });

  final int? categoryId;
  final String name;
  final double quantitySold;
  final double revenue;
  final double profit;
  final double contributionPercent;
}

class VelocityRow {
  const VelocityRow({
    this.productId,
    required this.name,
    required this.quantity,
    required this.value,
    this.isDeadStock = false,
    this.ageDays = 0,
  });

  final int? productId;
  final String name;
  final double quantity;
  final double value;
  final bool isDeadStock;
  final double ageDays;
}

class ProductVelocityData {
  const ProductVelocityData({
    required this.fastMoving,
    required this.slowMoving,
  });

  final List<VelocityRow> fastMoving;
  final List<VelocityRow> slowMoving;

  static const empty = ProductVelocityData(fastMoving: [], slowMoving: []);
}

class ExecutiveDashboardData {
  const ExecutiveDashboardData({
    required this.totalRevenue,
    required this.totalProfit,
    required this.netCashFlow,
    required this.returnRatePercent,
    required this.inventoryValue,
    required this.receivableDebts,
    required this.payableDebts,
    this.topProductName,
    this.topCustomerName,
    this.topCashierName,
  });

  final double totalRevenue;
  final double totalProfit;
  final double netCashFlow;
  final double returnRatePercent;
  final double inventoryValue;
  final double receivableDebts;
  final double payableDebts;
  final String? topProductName;
  final String? topCustomerName;
  final String? topCashierName;

  static const empty = ExecutiveDashboardData(
    totalRevenue: 0,
    totalProfit: 0,
    netCashFlow: 0,
    returnRatePercent: 0,
    inventoryValue: 0,
    receivableDebts: 0,
    payableDebts: 0,
  );
}

class PeriodMetrics {
  const PeriodMetrics({
    required this.revenue,
    required this.profit,
    required this.invoiceCount,
    required this.netCashFlow,
    required this.returnRate,
  });

  final double revenue;
  final double profit;
  final int invoiceCount;
  final double netCashFlow;
  final double returnRate;
}

class ComparativeAnalyticsData {
  const ComparativeAnalyticsData({
    required this.current,
    required this.previous,
    required this.revenueChangePercent,
    required this.profitChangePercent,
    required this.cashFlowChangePercent,
    required this.returnRateChangePoints,
  });

  final PeriodMetrics current;
  final PeriodMetrics previous;
  final double revenueChangePercent;
  final double profitChangePercent;
  final double cashFlowChangePercent;
  final double returnRateChangePoints;

  static final empty = ComparativeAnalyticsData(
    current: PeriodMetrics(revenue: 0, profit: 0, invoiceCount: 0, netCashFlow: 0, returnRate: 0),
    previous: PeriodMetrics(revenue: 0, profit: 0, invoiceCount: 0, netCashFlow: 0, returnRate: 0),
    revenueChangePercent: 0,
    profitChangePercent: 0,
    cashFlowChangePercent: 0,
    returnRateChangePoints: 0,
  );
}

class AnalyticsDateRange {
  const AnalyticsDateRange({required this.from, required this.to});
  final DateTime from;
  final DateTime to;
}

class ComparativeDateRanges {
  const ComparativeDateRanges({
    required this.current,
    required this.previous,
  });

  final AnalyticsDateRange current;
  final AnalyticsDateRange previous;
}
