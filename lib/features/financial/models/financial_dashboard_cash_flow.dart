/// Period cash-flow KPIs sourced entirely from FinancialLedgerRepository.
/// totalInflow, totalOutflow, netCashFlow: from getSummary(filter).
/// cashBalance: from getSummaryAllTime() -- all-time ledger net.
/// CASH ONLY. No accrual, no COGS, no profitability metric.
class FinancialDashboardCashFlow {
  const FinancialDashboardCashFlow({
    required this.totalInflow,
    required this.totalOutflow,
    required this.netCashFlow,
    required this.cashBalance,
  });

  /// Sum of all inflow events in the selected period.
  /// Includes: SALE_CASH + CUSTOMER_PAYMENT + OTHER_INCOME + SUPPLIER_REFUND.
  final double totalInflow;

  /// Sum of all outflow events in the selected period.
  /// Includes: PURCHASE_CASH + SUPPLIER_PAYMENT + EXPENSE + RETURN_REFUND.
  final double totalOutflow;

  /// Period net: totalInflow - totalOutflow (as stored from getSummary).
  final double netCashFlow;

  /// All-time accumulated ledger net (calculated cash balance).
  /// UI label: "\u0627\u0644\u0631\u0635\u064a\u062f \u0627\u0644\u0646\u0642\u062f\u064a \u0627\u0644\u0645\u062d\u0633\u0648\u0628".
  /// Cached 45 s. Does NOT change when the date filter changes.
  final double cashBalance;

  static const empty = FinancialDashboardCashFlow(
    totalInflow: 0,
    totalOutflow: 0,
    netCashFlow: 0,
    cashBalance: 0,
  );

  /// Derived net: totalInflow - totalOutflow computed locally.
  /// Should match [netCashFlow] within floating-point tolerance.
  double get computedNetCashFlow => totalInflow - totalOutflow;

  /// True when [netCashFlow] matches [computedNetCashFlow] within 0.01.
  /// Use for debug assertions; should always be true in production.
  bool get isNetConsistent => (computedNetCashFlow - netCashFlow).abs() < 0.01;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardCashFlow &&
          runtimeType == other.runtimeType &&
          totalInflow == other.totalInflow &&
          totalOutflow == other.totalOutflow &&
          netCashFlow == other.netCashFlow &&
          cashBalance == other.cashBalance;

  @override
  int get hashCode =>
      Object.hash(totalInflow, totalOutflow, netCashFlow, cashBalance);

  FinancialDashboardCashFlow copyWith({
    double? totalInflow,
    double? totalOutflow,
    double? netCashFlow,
    double? cashBalance,
  }) =>
      FinancialDashboardCashFlow(
        totalInflow: totalInflow ?? this.totalInflow,
        totalOutflow: totalOutflow ?? this.totalOutflow,
        netCashFlow: netCashFlow ?? this.netCashFlow,
        cashBalance: cashBalance ?? this.cashBalance,
      );
}
