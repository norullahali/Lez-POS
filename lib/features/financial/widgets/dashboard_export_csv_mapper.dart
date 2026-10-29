import '../../reports/core/exports/report_export_models.dart';
import '../models/dashboard_export.dart';

/// Maps [DashboardExportDocument] to [ReportExportRequest] for CSV export (B42 Stage 1).
class DashboardExportCsvMapper {
  DashboardExportCsvMapper._();

  static const reportId = 'financial_dashboard';

  static const _colSection = '\u0627\u0644\u0642\u0633\u0645';
  static const _colType = '\u0627\u0644\u0646\u0648\u0639';
  static const _colTitle = '\u0627\u0644\u0639\u0646\u0648\u0627\u0646';
  static const _colValue = '\u0627\u0644\u0642\u064a\u0645\u0629';
  static const _colDetails = '\u0627\u0644\u062a\u0641\u0627\u0635\u064a\u0644';

  static const _typeKpi = '\u0645\u0624\u0634\u0631';
  static const _typeChart = '\u0645\u062e\u0637\u0637';
  static const _typeInsight = '\u0631\u0624\u064a\u0629';
  static const _typeAlert = '\u062a\u0646\u0628\u064a\u0647';
  static const _typeActivity = '\u0646\u0634\u0627\u0637';
  static const _typeDisclaimer = '\u062a\u0646\u0628\u064a\u0647 \u062a\u0635\u062f\u064a\u0631';
  static const _typeEmpty = '\u0641\u0627\u0631\u063a';

  static const disclaimerSnapshot =
      '\u0647\u0630\u0627 \u0645\u0644\u062e\u0635 \u0644\u062d\u0627\u0644\u0629 \u0627\u0644\u0644\u0648\u062d\u0629 \u0627\u0644\u062d\u0627\u0644\u064a\u0629 \u0648\u0644\u064a\u0633 \u0628\u064a\u0627\u0646\u0627\u064b \u0645\u062d\u0627\u0633\u0628\u064a\u0627\u064b \u0645\u0639\u062a\u0645\u062f\u0627\u064b.';

  static const disclaimerPeriodSales =
      '\u0625\u062c\u0645\u0627\u0644\u064a \u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0641\u062a\u0631\u0629 \u0645\u0642\u064a\u0627\u0633 \u0627\u0633\u062a\u062d\u0642\u0627\u0642\u064a \u0648\u0642\u062f \u064a\u0634\u0645\u0644 \u0641\u0648\u0627\u062a\u064a\u0631 \u0645\u0631\u062a\u062c\u0639\u0629 \u0643\u0645\u0627 \u0641\u064a \u0627\u0644\u0644\u0648\u062d\u0629.';

  static const _headers = [
    _colSection,
    _colType,
    _colTitle,
    _colValue,
    _colDetails,
  ];

  static ReportExportRequest toRequest(
    DashboardExportDocument document, {
    String? generatedBy,
  }) {
    final rows = <List<String>>[
      _disclaimerRow(disclaimerSnapshot),
      _disclaimerRow(disclaimerPeriodSales),
      ..._sectionRows(document),
    ];

    return ReportExportRequest(
      metadata: ReportExportMetadata(
        reportId: reportId,
        titleAr: document.title,
        generatedAt: document.generatedAt,
        filterSummary: document.filterSummary,
        generatedBy: generatedBy,
      ),
      format: ReportExportFormat.csv,
      headers: _headers,
      rows: rows,
    );
  }

  static List<String> _disclaimerRow(String text) => [
        '\u2014',
        _typeDisclaimer,
        text,
        '\u2014',
        '\u2014',
      ];

  static List<List<String>> _sectionRows(DashboardExportDocument document) {
    final out = <List<String>>[];
    for (final section in document.sections) {
      if (!section.hasContent) {
        out.add([
          section.title,
          _typeEmpty,
          '\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u064a\u0627\u0646\u0627\u062a',
          '\u2014',
          '\u2014',
        ]);
        continue;
      }

      for (final kpi in section.kpis) {
        out.add([
          section.title,
          _typeKpi,
          kpi.title,
          kpi.value,
          kpi.subtitle ?? '\u2014',
        ]);
      }

      for (final chart in section.charts) {
        for (final row in chart.rows) {
          final details = row.secondaryValue == null
              ? chart.title
              : '${chart.title} | ${row.secondaryValue}';
          out.add([
            section.title,
            _typeChart,
            row.label,
            row.primaryValue,
            details,
          ]);
        }
      }

      for (final insight in section.insights) {
        out.add([
          section.title,
          _typeInsight,
          insight.title,
          '\u2014',
          insight.body,
        ]);
      }

      for (final alert in section.alerts) {
        out.add([
          section.title,
          _typeAlert,
          alert.title,
          '\u2014',
          alert.body,
        ]);
      }

      for (final activity in section.activityRows) {
        out.add([
          section.title,
          _typeActivity,
          activity.typeLabel,
          activity.amountLabel,
          '${activity.timestampLabel} | ${activity.description}',
        ]);
      }
    }
    return out;
  }
}