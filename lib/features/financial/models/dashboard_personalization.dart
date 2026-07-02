/// Presentation-only Financial Dashboard UI preferences (Phase 5.3.6 / 5.3.9).
///
/// **Ownership:** held by [_FinancialDashboardScreenState._personalization] only.
/// Serialized by [DashboardPersonalizationStore]; never stored in providers or
/// repositories.
///
/// **Immutability:** const constructor; updates via [copyWith] / [toggleCollapsed].
/// Equality ([==] / [hashCode]) supports screen- and store-level duplicate-write guards.
///
/// **Lifecycle:** loaded once when the dashboard opens via
/// [DashboardPersonalizationStore.load]; persisted on user change via the screen's
/// [_persistPersonalization]. Discarded when the screen is disposed.
///
/// **Serialization responsibility:** [toJson] / [fromJson] encode presentation
/// preferences only — visibility toggles, collapse state, display density.
/// Unknown or malformed JSON fields fall back to constructor defaults.
///
/// **Future extensibility:** optional visibility toggles and [DashboardSectionId]
/// support additional sections without analytics or repository changes.
///
/// Controls section visibility, collapse state, and display density only —
/// not accounting rules, not business logic, not workflow triggers.
class DashboardPersonalization {
  const DashboardPersonalization({
    this.showInsights = true,
    this.showAlerts = true,
    this.showAnalyticsCharts = true,
    this.showRecentActivity = true,
    this.collapsedSections = const {},
    this.displayDensity = DashboardDisplayDensity.comfortable,
  });

  /// Whether the insights section is mounted (default: visible).
  final bool showInsights;
  /// Whether the alerts section is mounted (default: visible).
  final bool showAlerts;
  /// Whether the analytics charts section is mounted (default: visible).
  final bool showAnalyticsCharts;
  /// Whether the recent activity section is mounted (default: visible).
  final bool showRecentActivity;
  /// Sections currently collapsed in the UI.
  ///
  /// Retained when a section is hidden and restored on re-show; persisted locally.
  final Set<DashboardSectionId> collapsedSections;
  /// Inter-section spacing density (default: [DashboardDisplayDensity.comfortable]).
  final DashboardDisplayDensity displayDensity;

  static const _kCompactSectionSpacing = 12.0;
  static const _kComfortableSectionSpacing = 16.0;

  /// Vertical gap between dashboard sections.
  ///
  /// Presentation spacing only — does not alter inner section card padding.
  /// Comfortable: 16px (pre-5.3.6 default). Compact: 12px.
  double get sectionSpacing =>
      displayDensity == DashboardDisplayDensity.compact
          ? _kCompactSectionSpacing
          : _kComfortableSectionSpacing;

  bool isCollapsed(DashboardSectionId section) =>
      collapsedSections.contains(section);

  DashboardPersonalization copyWith({
    bool? showInsights,
    bool? showAlerts,
    bool? showAnalyticsCharts,
    bool? showRecentActivity,
    Set<DashboardSectionId>? collapsedSections,
    DashboardDisplayDensity? displayDensity,
  }) {
    return DashboardPersonalization(
      showInsights: showInsights ?? this.showInsights,
      showAlerts: showAlerts ?? this.showAlerts,
      showAnalyticsCharts: showAnalyticsCharts ?? this.showAnalyticsCharts,
      showRecentActivity: showRecentActivity ?? this.showRecentActivity,
      collapsedSections: collapsedSections ?? this.collapsedSections,
      displayDensity: displayDensity ?? this.displayDensity,
    );
  }

  /// Returns a new instance with [section] collapse toggled (immutable update).
  DashboardPersonalization toggleCollapsed(DashboardSectionId section) {
    final next = Set<DashboardSectionId>.from(collapsedSections);
    if (next.contains(section)) {
      next.remove(section);
    } else {
      next.add(section);
    }
    return copyWith(collapsedSections: next);
  }

  /// JSON map for [DashboardPersonalizationStore] (Phase 5.3.9).
  ///
  /// Bounded payload: five scalar fields — O(1) serialization complexity.
  Map<String, dynamic> toJson() => {
        'showInsights': showInsights,
        'showAlerts': showAlerts,
        'showAnalyticsCharts': showAnalyticsCharts,
        'showRecentActivity': showRecentActivity,
        'collapsedSections': collapsedSections.map((e) => e.name).toList()
          ..sort(),
        'displayDensity': displayDensity.name,
      };

  /// Restores personalization from [json].
  ///
  /// **Safe fallback:** unknown enum names, wrong types, or missing keys use
  /// constructor defaults — never throws.
  factory DashboardPersonalization.fromJson(Map<String, dynamic> json) {
    return DashboardPersonalization(
      showInsights: json['showInsights'] as bool? ?? true,
      showAlerts: json['showAlerts'] as bool? ?? true,
      showAnalyticsCharts: json['showAnalyticsCharts'] as bool? ?? true,
      showRecentActivity: json['showRecentActivity'] as bool? ?? true,
      collapsedSections: _collapsedSectionsFromJson(json['collapsedSections']),
      displayDensity: _displayDensityFromJson(json['displayDensity']),
    );
  }

  static Set<DashboardSectionId> _collapsedSectionsFromJson(Object? raw) {
    final collapsed = <DashboardSectionId>{};
    if (raw is! List) return collapsed;
    for (final entry in raw) {
      if (entry is! String) continue;
      for (final section in DashboardSectionId.values) {
        if (section.name == entry) {
          collapsed.add(section);
          break;
        }
      }
    }
    return collapsed;
  }

  static DashboardDisplayDensity _displayDensityFromJson(Object? raw) {
    if (raw is! String) return DashboardDisplayDensity.comfortable;
    for (final value in DashboardDisplayDensity.values) {
      if (value.name == raw) return value;
    }
    return DashboardDisplayDensity.comfortable;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DashboardPersonalization &&
        showInsights == other.showInsights &&
        showAlerts == other.showAlerts &&
        showAnalyticsCharts == other.showAnalyticsCharts &&
        showRecentActivity == other.showRecentActivity &&
        displayDensity == other.displayDensity &&
        _setEquals(collapsedSections, other.collapsedSections);
  }

  @override
  int get hashCode => Object.hash(
        showInsights,
        showAlerts,
        showAnalyticsCharts,
        showRecentActivity,
        displayDensity,
        Object.hashAllUnordered(collapsedSections),
      );

  static bool _setEquals(
    Set<DashboardSectionId> a,
    Set<DashboardSectionId> b,
  ) =>
      a.length == b.length && a.containsAll(b);
}

/// Collapsible dashboard section identifiers (Phase 5.3.6).
enum DashboardSectionId {
  cashFlow,
  analytics,
  insights,
  alerts,
  supplementaryKpi,
  recentActivity,
}

/// UI density for dashboard inter-section spacing (Phase 5.3.6).
enum DashboardDisplayDensity {
  comfortable,
  compact,
}

extension DashboardSectionIdLabels on DashboardSectionId {
  String get labelAr => switch (this) {
        DashboardSectionId.cashFlow => '\u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
        DashboardSectionId.analytics =>
          '\u0627\u0644\u062a\u062d\u0644\u064a\u0644\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
        DashboardSectionId.insights => '\u0631\u0624\u0649 \u0645\u0627\u0644\u064a\u0629',
        DashboardSectionId.alerts => '\u062a\u0646\u0628\u064a\u0647\u0627\u062a \u0645\u0627\u0644\u064a\u0629',
        DashboardSectionId.supplementaryKpi =>
          '\u0627\u0644\u0645\u0624\u0634\u0631\u0627\u062a \u0627\u0644\u062a\u0643\u0645\u064a\u0644\u064a\u0629',
        DashboardSectionId.recentActivity =>
          '\u0622\u062e\u0631 \u0627\u0644\u062d\u0631\u0643\u0627\u062a',
      };
}