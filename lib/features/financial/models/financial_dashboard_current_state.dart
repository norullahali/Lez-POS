/// Current-state and supplementary KPIs sourced from FinancialDashboardRepository.
/// customerDebt and supplierDebt are always current (no date filter).
/// totalSales, cardSales, sessionDifference are period-filtered.
///
/// IMPORTANT -- totalSales is an ACCRUAL metric (GROSS SALES before returns).
/// It must never be added to or subtracted from any cash flow formula.
/// In the UI always label it as "\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0645\u0628\u064a\u0639\u0627\u062a (\u0634\u0627\u0645\u0644 \u0627\u0644\u0622\u062c\u0644)".
class FinancialDashboardCurrentState {
  const FinancialDashboardCurrentState({
    required this.customerDebt,
    required this.supplierDebt,
    required this.totalSales,
    required this.cardSales,
    required this.sessionDifference,
  });

  /// Total outstanding receivables: SUM(customer_accounts.current_balance WHERE > 0).
  /// Always current -- ignores date filter.
  final double customerDebt;

  /// Total outstanding payables: SUM(supplier_accounts.current_balance WHERE > 0).
  /// Always current -- ignores date filter.
  final double supplierDebt;

  /// GROSS SALES for the period: SUM(sales_invoices.total WHERE sale_date IN [start, end)).
  ///
  /// Includes ALL invoices regardless of invoiceStatus:
  ///   - completed invoices (normal sales)
  ///   - returned invoices (invoiceStatus = 'returned') -- their original total remains
  ///
  /// Returns (cash refunds) are separately represented as RETURN_REFUND outflow entries
  /// in the Cash Ledger -- they are NOT subtracted here.
  ///
  /// This is an ACCRUAL metric -- it includes credit/\u0622\u062c\u0644 (debt) sales.
  /// Do NOT subtract from or add to any cash flow KPI.
  /// Do NOT present as "Net Sales" or "\u0635\u0627\u0641\u064a \u0627\u0644\u0645\u0628\u064a\u0639\u0627\u062a" in the UI without explicit return deduction.
  final double totalSales;

  /// Total card payment revenue (period) -- non-cash, supplementary.
  /// Source: SUM(sales_invoices.card_paid WHERE sale_date IN [start, end)).
  final double cardSales;

  /// Net cash discrepancy across all CLOSED sessions in period.
  /// Source: SUM(pos_sessions.cash_difference WHERE is_closed = 1 AND closed_at IN [start, end)).
  /// Negative = shortage, positive = overage.
  final double sessionDifference;

  static const empty = FinancialDashboardCurrentState(
    customerDebt: 0,
    supplierDebt: 0,
    totalSales: 0,
    cardSales: 0,
    sessionDifference: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardCurrentState &&
          runtimeType == other.runtimeType &&
          customerDebt == other.customerDebt &&
          supplierDebt == other.supplierDebt &&
          totalSales == other.totalSales &&
          cardSales == other.cardSales &&
          sessionDifference == other.sessionDifference;

  @override
  int get hashCode => Object.hash(
        customerDebt,
        supplierDebt,
        totalSales,
        cardSales,
        sessionDifference,
      );

  FinancialDashboardCurrentState copyWith({
    double? customerDebt,
    double? supplierDebt,
    double? totalSales,
    double? cardSales,
    double? sessionDifference,
  }) =>
      FinancialDashboardCurrentState(
        customerDebt: customerDebt ?? this.customerDebt,
        supplierDebt: supplierDebt ?? this.supplierDebt,
        totalSales: totalSales ?? this.totalSales,
        cardSales: cardSales ?? this.cardSales,
        sessionDifference: sessionDifference ?? this.sessionDifference,
      );
}