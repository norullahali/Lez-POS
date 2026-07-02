import 'package:flutter/material.dart';

/// Presentation-only quick action descriptor (Phase 5.3.8).
///
/// **Ownership:** built by [DashboardQuickActionsBuilder]; rendered by
/// [DashboardQuickActionsSection] and [DashboardQuickActionCard].
///
/// **Immutability:** const constructor; all fields are final. Instances are
/// created once in the builder catalog and passed down read-only.
///
/// **Lifecycle:** assembled at section build time; never persisted, never
/// mutated, never cached outside the widget tree.
///
/// **Boundary:** display metadata only — no repository references, no
/// providers, no navigation routes, no permission logic.
class DashboardQuickAction {
  const DashboardQuickAction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.enabled = true,
  });

  /// Stable action identifier for future navigation wiring (Phase 5.3.9+).
  final DashboardQuickActionId id;

  /// Arabic action title shown on the card header row.
  final String title;

  /// Arabic subtitle describing the intended workflow destination.
  final String subtitle;

  /// Material icon rendered inside the accent container on the card.
  final IconData icon;

  /// Whether the card accepts taps (foundation: all catalog actions enabled).
  final bool enabled;
}

/// Certified Financial Dashboard quick action identifiers (Phase 5.3.8).
///
/// **Ordering:** enum declaration order mirrors [DashboardQuickActionsBuilder]
/// catalog order — do not reorder without updating the builder list.
///
/// **Boundary:** identifiers only; no route names or permission flags.
enum DashboardQuickActionId {
  /// Cash ledger workflow shortcut.
  cashLedger,

  /// Financial reports center shortcut.
  financialReports,

  /// Customer accounts management shortcut.
  customers,

  /// Supplier accounts management shortcut.
  suppliers,

  /// Sales activity shortcut.
  sales,

  /// Purchase / inventory intake shortcut.
  purchases,
}
