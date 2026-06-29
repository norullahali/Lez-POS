import "financial_dashboard_cash_flow.dart";
import "financial_dashboard_current_state.dart";

/// Combined dashboard snapshot consumed by the Financial Dashboard screen.
/// generatedAt records when the snapshot was assembled for debugging / staleness display.
class FinancialDashboardSummary {
  const FinancialDashboardSummary({
    required this.cashFlow,
    required this.currentState,
    required this.generatedAt,
  });

  final FinancialDashboardCashFlow cashFlow;
  final FinancialDashboardCurrentState currentState;
  final DateTime generatedAt;

  static FinancialDashboardSummary get empty => FinancialDashboardSummary(
        cashFlow: FinancialDashboardCashFlow.empty,
        currentState: FinancialDashboardCurrentState.empty,
        generatedAt: DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinancialDashboardSummary &&
          runtimeType == other.runtimeType &&
          cashFlow == other.cashFlow &&
          currentState == other.currentState &&
          generatedAt == other.generatedAt;

  @override
  int get hashCode => Object.hash(cashFlow, currentState, generatedAt);

  FinancialDashboardSummary copyWith({
    FinancialDashboardCashFlow? cashFlow,
    FinancialDashboardCurrentState? currentState,
    DateTime? generatedAt,
  }) =>
      FinancialDashboardSummary(
        cashFlow: cashFlow ?? this.cashFlow,
        currentState: currentState ?? this.currentState,
        generatedAt: generatedAt ?? this.generatedAt,
      );
}