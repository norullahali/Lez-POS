import 'package:flutter/material.dart';

/// Presentation-only dashboard health / system status descriptor (Phase 5.6).
///
/// **Ownership:** built by [DashboardHealthStatusBuilder]; rendered by
/// [DashboardHealthStatusSection] and [DashboardHealthStatusCard].
///
/// **Immutability:** const constructor; all fields are final. Instances are
/// created in the builder catalog and passed down read-only.
///
/// **Lifecycle:** assembled at section build time from the static catalog;
/// never persisted, never mutated, never cached outside the widget tree.
///
/// **Presentation boundary:** display metadata only — no repository, providers,
/// SQL, monitoring engine, diagnostics, or persistence.
///
/// **Future extensibility:** [id] supports future monitoring-service wiring;
/// [status] and [timestamp] support live health updates without data-layer
/// changes in this phase.
class DashboardHealthStatusItem {
  const DashboardHealthStatusItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.icon,
    required this.accentColor,
    required this.timestamp,
  });

  /// Stable health item identifier for future monitoring wiring.
  final DashboardHealthStatusId id;

  /// Arabic health domain title shown on the card header row.
  final String title;

  /// Arabic subtitle describing the current health observation.
  final String subtitle;

  /// Operational status level driving accent bar and status chip styling.
  final DashboardSystemStatus status;

  /// Material icon rendered inside the accent container on the card.
  final IconData icon;

  /// Presentation accent color for the icon container and icon tint.
  final Color accentColor;

  /// Last-checked timestamp displayed below the subtitle (presentation only).
  final DateTime timestamp;
}

/// Certified Financial Dashboard health / system status identifiers (Phase 5.6).
///
/// **Ordering:** enum declaration order mirrors [DashboardHealthStatusBuilder]
/// catalog order — do not reorder without updating the builder list.
///
/// **Boundary:** identifiers only; no service names, probe endpoints, or
/// persistence keys.
enum DashboardHealthStatusId {
  /// Database connectivity and availability.
  database,

  /// Scheduled backup completion status.
  backup,

  /// Data synchronization lag and health.
  sync,

  /// Local service process availability.
  services,

  /// Financial data integrity scan results.
  dataIntegrity,

  /// Overall system readiness assessment.
  systemReadiness,
}

/// Operational status levels for dashboard presentation (Phase 5.6).
///
/// **Status mapping:** accent bar and chip colors/labels resolved by
/// [DashboardHealthStatusBuilder.statusAccentFor] and [statusLabelAr].
///
/// **Demo catalog note:** [offline] is fully mapped but not shown in the
/// foundation catalog — reserved for live monitoring integration.
enum DashboardSystemStatus {
  /// All checks passed — green accent and chip.
  healthy,

  /// Degraded or attention required — amber accent and chip.
  warning,

  /// Service unreachable — red accent and chip (not in demo catalog).
  offline,

  /// Status pending or indeterminate — neutral accent and chip.
  unknown,
}
