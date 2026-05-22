enum ReportTabId {
  daily,
  monthly,
  topProducts,
  inventory,
  purchases,
  topCustomers,
  customerDebts,
  supplierDebts,
  profitAnalysis,
  cashFlow,
  returnImpact,
  inventoryMovement,
  taxReports,
  employeePerformance,
  hourlyHeatmap,
  categoryPerformance,
  productVelocity,
  executiveDashboard,
  comparativeAnalytics,
}

extension ReportTabIdX on ReportTabId {
  int get tabIndex => index;

  static ReportTabId? fromIndex(int index) {
    if (index < 0 || index >= ReportTabId.values.length) return null;
    return ReportTabId.values[index];
  }

  String get cachePrefix => 'report_${name}_';

  bool get isAdvanced => index >= 8;
}
