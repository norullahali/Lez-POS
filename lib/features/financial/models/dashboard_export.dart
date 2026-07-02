/// Presentation-only export structures for the Financial Dashboard (Phase 5.3.7).
///
/// **Ownership:** built by [DashboardExportBuilder]; consumed by
/// [DashboardExportControls] placeholders and future PDF / print / clipboard
/// renderers.
///
/// **Immutability:** const constructors; all fields are final.
///
/// **Lifecycle:** ephemeral — created on export menu open, discarded after
/// placeholder action or menu dismiss; never persisted or stored in providers.
///
/// **Boundary:** strings and formatted values only — no repository access,
/// no provider state, no SQL, no business logic.
class DashboardExportDocument {
  const DashboardExportDocument({
    required this.title,
    required this.subtitle,
    required this.filterSummary,
    required this.generatedAt,
    required this.sections,
  });

  /// Dashboard header title (Arabic) — mirrors on-screen header.
  final String title;

  /// Dashboard header subtitle (Arabic) — mirrors on-screen header.
  final String subtitle;

  /// Human-readable applied filter summary from [DashboardFilter.dateFilter].
  final String filterSummary;

  /// Snapshot timestamp (presentation metadata only; not a data-layer audit time).
  final DateTime generatedAt;

  /// Ordered export sections — certified dashboard sequence after
  /// [DashboardPersonalization] visibility filtering.
  final List<DashboardExportSection> sections;

  /// Plain-text summary for future clipboard / print pipelines.
  ///
  /// Presentation serialization only — does not mutate or persist data.
  String toPlainTextSummary() {
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln(subtitle)
      ..writeln(filterSummary)
      ..writeln('---');

    for (final section in sections) {
      buffer.writeln(section.title);
      if (!section.hasContent) {
        buffer.writeln('  (no data loaded)');
        buffer.writeln();
        continue;
      }
      for (final kpi in section.kpis) {
        buffer.write('  ${kpi.title}: ${kpi.value}');
        if (kpi.subtitle != null) {
          buffer.write(' (${kpi.subtitle})');
        }
        buffer.writeln();
      }
      for (final chart in section.charts) {
        buffer.writeln('  ${chart.title}');
        for (final row in chart.rows) {
          buffer.write('    ${row.label}: ${row.primaryValue}');
          if (row.secondaryValue != null) {
            buffer.write(' / ${row.secondaryValue}');
          }
          buffer.writeln();
        }
      }
      for (final insight in section.insights) {
        buffer.writeln('  • ${insight.title}');
        buffer.writeln('    ${insight.body}');
      }
      for (final alert in section.alerts) {
        buffer.writeln('  ! ${alert.title}');
        buffer.writeln('    ${alert.body}');
      }
      for (final row in section.activityRows) {
        buffer.writeln('  ${row.timestampLabel} | ${row.typeLabel} | ${row.amountLabel}');
        if (row.description.isNotEmpty) {
          buffer.writeln('    ${row.description}');
        }
      }
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }
}

/// Identifies an export section aligned with dashboard layout (Phase 5.3.6).
enum DashboardExportSectionKind {
  cashFlow,
  analytics,
  insights,
  alerts,
  supplementaryKpi,
  recentActivity,
}

/// One exportable dashboard section with presentation-only payloads.
///
/// **Immutability:** const constructor; payload lists are fixed at build time.
///
/// **Visibility:** optional sections omitted when hidden via personalization;
/// core sections (cash flow, supplementary KPI) always appear when built.
class DashboardExportSection {
  const DashboardExportSection({
    required this.kind,
    required this.title,
    required this.visible,
    this.collapsed = false,
    this.kpis = const [],
    this.charts = const [],
    this.insights = const [],
    this.alerts = const [],
    this.activityRows = const [],
  });

  /// Section identity — maps to certified dashboard layout.
  final DashboardExportSectionKind kind;

  /// Arabic section title — sourced from [DashboardSectionId.labelAr].
  final String title;

  /// Whether the section is mounted per [DashboardPersonalization].
  final bool visible;

  /// Whether the section is collapsed on screen (metadata for future renderers).
  ///
  /// Foundation phase exports full section payloads regardless of collapse.
  final bool collapsed;

  /// Period / state KPI rows (cash flow, supplementary).
  final List<DashboardExportKpi> kpis;

  /// Trend and composition chart tabular rows.
  final List<DashboardExportChart> charts;

  /// Insight title/body blocks.
  final List<DashboardExportTextItem> insights;

  /// Alert title/body blocks.
  final List<DashboardExportTextItem> alerts;

  /// Recent activity rows for the selected period.
  final List<DashboardExportActivityRow> activityRows;

  /// True when any payload list contains at least one item.
  bool get hasContent =>
      kpis.isNotEmpty ||
      charts.isNotEmpty ||
      insights.isNotEmpty ||
      alerts.isNotEmpty ||
      activityRows.isNotEmpty;
}

/// Formatted KPI row for export (pre-formatted display strings).
class DashboardExportKpi {
  const DashboardExportKpi({
    required this.title,
    required this.value,
    this.subtitle,
  });

  /// Arabic KPI label — mirrors on-screen tile title.
  final String title;

  /// Pre-formatted monetary or numeric display value.
  final String value;

  /// Optional Arabic subtitle (e.g. period disclaimer, current-state note).
  final String? subtitle;
}

/// Chart export category (trend time-series vs composition breakdown).
enum DashboardExportChartKind { trend, composition }

/// Tabular chart export block for future PDF / print renderers.
class DashboardExportChart {
  const DashboardExportChart({
    required this.title,
    required this.kind,
    required this.rows,
  });

  /// Arabic chart title — mirrors analytics section chart headers.
  final String title;

  final DashboardExportChartKind kind;

  /// Bucket or slice rows with formatted values.
  final List<DashboardExportChartRow> rows;
}

/// One chart data row (label + one or two formatted values).
class DashboardExportChartRow {
  const DashboardExportChartRow({
    required this.label,
    required this.primaryValue,
    this.secondaryValue,
  });

  /// Bucket or event-type label (display-ready Arabic where applicable).
  final String label;

  /// Primary formatted value (inflow or single composition amount).
  final String primaryValue;

  /// Secondary formatted value (outflow for trend rows; null for composition).
  final String? secondaryValue;
}

/// Title + body text block reused for insights and alerts export.
class DashboardExportTextItem {
  const DashboardExportTextItem({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

/// Recent activity row for export (all fields pre-formatted for display).
class DashboardExportActivityRow {
  const DashboardExportActivityRow({
    required this.timestampLabel,
    required this.typeLabel,
    required this.amountLabel,
    required this.description,
  });

  final String timestampLabel;
  final String typeLabel;
  final String amountLabel;
  final String description;
}