import 'package:flutter/material.dart';

/// Presentation-only financial observation derived from certified analytics data.
///
/// **Immutability:** const constructor; all fields are final.
///
/// **Ownership:** built by [DashboardAnalyticsInsightsBuilder]; rendered by
/// [DashboardInsightCard]; never stored in providers or repositories.
///
/// **Lifecycle:** ephemeral — created in `dataBuilder`, discarded on rebuild.
///
/// **Future extensibility:** [kind] supports additional observation categories
/// without analytics model changes; optional fields stay out of this phase.
///
/// Not persisted — dashboard UX interpretations only, not business rules.
class DashboardAnalyticsInsight {
  const DashboardAnalyticsInsight({
    required this.kind,
    required this.title,
    required this.body,
    required this.icon,
    required this.accentColor,
  });

  final DashboardAnalyticsInsightKind kind;
  final String title;
  final String body;
  final IconData icon;
  final Color accentColor;
}

/// Categories of deterministic dashboard observations (Phase 5.3.4).
enum DashboardAnalyticsInsightKind {
  strongestIncomeSource,
  largestExpenseCategory,
  positiveCashFlowTrend,
  negativeCashFlowTrend,
  unusualConcentration,
}
