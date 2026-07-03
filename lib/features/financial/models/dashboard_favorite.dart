import 'package:flutter/material.dart';

/// Presentation-only dashboard favorite descriptor (Phase 5.5).
///
/// **Ownership:** built by [DashboardFavoritesBuilder]; rendered by
/// [DashboardFavoritesSection] and [DashboardFavoriteCard].
///
/// **Immutability:** const constructor; all fields are final. Instances are
/// created in the builder catalog and passed down read-only.
///
/// **Lifecycle:** assembled at section build time from the static catalog;
/// never persisted, never mutated, never cached outside the widget tree.
///
/// **Presentation boundary:** display metadata only — no repository, providers,
/// SQL, persistence, permissions, or navigation routes.
///
/// **Future extensibility:** [id] supports future user-pinning and persistence
/// wiring; [accentColor] and [enabled] support presentation without data-layer
/// changes in this phase.
class DashboardFavorite {
  const DashboardFavorite({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.enabled = true,
  });

  /// Stable favorite identifier for future pinning/persistence wiring.
  final DashboardFavoriteId id;

  /// Arabic favorite title shown on the card header row.
  final String title;

  /// Arabic subtitle describing the pinned workflow destination.
  final String subtitle;

  /// Material icon rendered inside the accent container on the card.
  final IconData icon;

  /// Presentation accent color for icon container, icon tint, and star indicator.
  final Color accentColor;

  /// Whether the card accepts taps (foundation: all catalog favorites enabled).
  final bool enabled;
}

/// Certified Financial Dashboard favorite identifiers (Phase 5.5).
///
/// **Ordering:** enum declaration order mirrors [DashboardFavoritesBuilder]
/// catalog order — do not reorder without updating the builder list.
///
/// **Boundary:** identifiers only; no route names, permission flags, or persistence keys.
enum DashboardFavoriteId {
  /// Cash ledger pinned shortcut.
  cashLedger,

  /// Sales activity pinned shortcut.
  sales,

  /// Purchases / inventory intake pinned shortcut.
  purchases,

  /// Financial reports center pinned shortcut.
  financialReports,

  /// Customer accounts pinned shortcut.
  customers,

  /// Supplier accounts pinned shortcut.
  suppliers,
}