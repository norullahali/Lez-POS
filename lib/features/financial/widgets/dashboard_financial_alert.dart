import 'package:flutter/material.dart';

/// Presentation-only financial alert requiring user attention (Phase 5.3.5).
///
/// **Immutability:** const constructor; all fields are final.
///
/// **Ownership:** built by [DashboardFinancialAlertsBuilder]; rendered by
/// [DashboardAlertCard]; never stored in providers or repositories.
///
/// **Lifecycle:** ephemeral — created in `dataBuilder`, discarded on rebuild.
///
/// **Future extensibility:** [kind] supports additional attention categories
/// without analytics model changes; optional fields stay out of this phase.
///
/// Informational only — not workflow triggers, not accounting decisions,
/// not business rules.
class DashboardFinancialAlert {
  const DashboardFinancialAlert({
    required this.kind,
    required this.title,
    required this.body,
    required this.icon,
    required this.accentColor,
  });

  final DashboardFinancialAlertKind kind;
  final String title;
  final String body;
  final IconData icon;
  final Color accentColor;
}

/// Alert categories for the Financial Dashboard (Phase 5.3.5).
enum DashboardFinancialAlertKind {
  negativeCashFlow,
  largeExpenseConcentration,
  noIncomeDetected,
  highSpendingPeriod,
  unusualCashImbalance,
}
