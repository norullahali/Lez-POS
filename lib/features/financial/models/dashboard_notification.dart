/// Presentation-only dashboard notification descriptor (Phase 5.4).
///
/// **Ownership:** built by [DashboardNotificationsBuilder]; rendered by
/// [DashboardNotificationsSection] and [DashboardNotificationCard].
///
/// **Immutability:** const constructor; all fields are final. Instances are
/// created in the builder catalog and passed down read-only.
///
/// **Lifecycle:** assembled at section build time from the static catalog;
/// never persisted, never mutated, never cached outside the widget tree.
///
/// **Presentation boundary:** display metadata only — no repository, providers,
/// SQL, notification engine, or persistence.
///
/// **Future extensibility:** [id] supports future engine wiring; [severity]
/// and [isRead] support read/unread and attention styling without data-layer
/// changes in this phase.
class DashboardNotification {
  const DashboardNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.isRead = false,
  });

  /// Stable notification identifier for future engine wiring.
  final String id;

  /// Arabic notification title shown on the card header row.
  final String title;

  /// Arabic notification body message.
  final String message;

  /// Visual severity level — drives accent color and icon via the builder.
  final DashboardNotificationSeverity severity;

  /// Presentation timestamp (static anchor in foundation catalog).
  final DateTime timestamp;

  /// Read flag for card styling only in this phase — static in the catalog;
  /// tap does not mutate read state until a notification engine is wired.
  final bool isRead;
}

/// Notification severity levels for dashboard presentation (Phase 5.4).
///
/// **Boundary:** presentation styling only; not business rules or alert logic.
///
/// Mapped to [AppColors] and Material icons by [DashboardNotificationsBuilder].
enum DashboardNotificationSeverity {
  /// Informational notice — [AppColors.info].
  info,

  /// Positive completion notice — [AppColors.success].
  success,

  /// Attention-required notice — [AppColors.warning].
  warning,

  /// Critical attention notice — [AppColors.error].
  error,
}