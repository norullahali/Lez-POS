import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lez_pos/features/financial/models/dashboard_export.dart';
import 'package:lez_pos/features/financial/screens/widgets/dashboard_export_controls.dart';
import 'package:lez_pos/features/financial/widgets/dashboard_export_csv_mapper.dart';
import 'package:lez_pos/features/financial/widgets/dashboard_export_helper.dart';
import 'package:lez_pos/features/reports/core/exports/report_export_models.dart';
import 'package:lez_pos/features/reports/core/providers/report_permissions.dart';

void main() {
  group('DashboardExportCsvMapper', () {
    test('includes disclaimers and preserves section order', () {
      final doc = _sampleDocument();
      final request = DashboardExportCsvMapper.toRequest(doc, generatedBy: 'admin');

      expect(request.format, ReportExportFormat.csv);
      expect(request.metadata.reportId, DashboardExportCsvMapper.reportId);
      expect(request.metadata.titleAr, doc.title);
      expect(request.metadata.filterSummary, doc.filterSummary);
      expect(request.metadata.generatedBy, 'admin');

      expect(request.rows.length, greaterThan(2));
      expect(request.rows[0][1], '\u062a\u0646\u0628\u064a\u0647 \u062a\u0635\u062f\u064a\u0631');
      expect(request.rows[0][2], DashboardExportCsvMapper.disclaimerSnapshot);
      expect(request.rows[1][2], DashboardExportCsvMapper.disclaimerPeriodSales);

      final dataRows = request.rows.skip(2).toList();
      expect(dataRows.first[0], '\u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a');
      final supplementaryIndex = dataRows.indexWhere(
        (r) => r[0] == '\u0627\u0644\u0645\u0624\u0634\u0631\u0627\u062a \u0627\u0644\u062a\u0643\u0645\u064a\u0644\u064a\u0629',
      );
      expect(supplementaryIndex, greaterThan(0));
    });

    test('maps KPI and chart rows deterministically', () {
      final doc = _sampleDocument();
      final rows = DashboardExportCsvMapper.toRequest(doc).rows.skip(2).toList();

      final kpiRow = rows.firstWhere((r) => r[1] == '\u0645\u0624\u0634\u0631');
      expect(kpiRow[2], '\u0627\u0644\u0631\u0635\u064a\u062f \u0627\u0644\u0646\u0642\u062f\u064a');
      expect(kpiRow[3], '1,000 \u062f.\u0639');

      final chartRow = rows.firstWhere((r) => r[1] == '\u0645\u062e\u0637\u0637');
      expect(chartRow[2], '\u0627\u0644\u0627\u062b\u0646\u064a\u0646');
      expect(chartRow[3], '500 \u062f.\u0639');
      expect(chartRow[4], contains('\u0627\u062a\u062c\u0627\u0647'));
    });

    test('empty section emits Arabic empty row', () {
      final doc = DashboardExportDocument(
        title: 't',
        subtitle: 's',
        filterSummary: 'f',
        generatedAt: DateTime(2026, 3, 1),
        sections: const [
          DashboardExportSection(
            kind: DashboardExportSectionKind.insights,
            title: '\u0631\u0624\u0649',
            visible: true,
          ),
        ],
      );

      final rows = DashboardExportCsvMapper.toRequest(doc).rows.skip(2);
      expect(rows.single[1], '\u0641\u0627\u0631\u063a');
      expect(rows.single[2], '\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u064a\u0627\u0646\u0627\u062a');
    });
  });

  group('DashboardExportDocument', () {
    test('hasExportableContent reflects section payloads', () {
      expect(_emptyDocument().hasExportableContent, isFalse);
      expect(_sampleDocument().hasExportableContent, isTrue);
    });

    test('toPlainTextSummary uses Arabic empty marker', () {
      final text = _emptyDocument().toPlainTextSummary();
      expect(text, contains('\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u064a\u0627\u0646\u0627\u062a'));
      expect(text, isNot(contains('no data loaded')));
    });
  });

  group('DashboardExportHelper permission and empty guards', () {
    testWidgets('denies CSV export without reportsExport permission', (tester) async {
      await tester.pumpWidget(_harness(
        canExport: false,
        onTrigger: (context, ref) => DashboardExportHelper.exportCsv(
          context: context,
          ref: ref,
          document: _sampleDocument(),
        ),
      ));

      await tester.tap(find.text('trigger'));
      await tester.pump();

      expect(find.textContaining('\u0635\u0644\u0627\u062d\u064a\u0629'), findsOneWidget);
    });

    testWidgets('denies copy summary without reportsExport permission', (tester) async {
      await tester.pumpWidget(_harness(
        canExport: false,
        onTrigger: (context, ref) => DashboardExportHelper.copySummary(
          context: context,
          ref: ref,
          document: _sampleDocument(),
        ),
      ));

      await tester.tap(find.text('trigger'));
      await tester.pump();

      expect(find.textContaining('\u0635\u0644\u0627\u062d\u064a\u0629'), findsOneWidget);
    });

    testWidgets('blocks CSV when document has no exportable content', (tester) async {
      await tester.pumpWidget(_harness(
        canExport: true,
        onTrigger: (context, ref) => DashboardExportHelper.exportCsv(
          context: context,
          ref: ref,
          document: _emptyDocument(),
        ),
      ));

      await tester.tap(find.text('trigger'));
      await tester.pump();

      expect(find.textContaining('\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u064a\u0627\u0646\u0627\u062a'), findsOneWidget);
    });

    testWidgets('blocks copy when document has no exportable content', (tester) async {
      var clipboardSetDataCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardSetDataCalls++;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(_harness(
        canExport: true,
        onTrigger: (context, ref) => DashboardExportHelper.copySummary(
          context: context,
          ref: ref,
          document: _emptyDocument(),
        ),
      ));

      await tester.tap(find.text('trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboardSetDataCalls, 0);
      expect(find.textContaining('\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u064a\u0627\u0646\u0627\u062a'), findsOneWidget);
    });

    testWidgets('copies summary when document has exportable content', (tester) async {
      var clipboardSetDataCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardSetDataCalls++;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(_harness(
        canExport: true,
        onTrigger: (context, ref) => DashboardExportHelper.copySummary(
          context: context,
          ref: ref,
          document: _sampleDocument(),
        ),
      ));

      await tester.tap(find.text('trigger'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboardSetDataCalls, 1);
      expect(find.textContaining('\u062a\u0645 \u0646\u0633\u062e'), findsOneWidget);
    });
  });

  group('DashboardExportButton', () {
    testWidgets('is disabled when export permission is missing', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            canExportReportsProvider.overrideWith((ref) => false),
          ],
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: DashboardExportButton(onPrepareDocument: _sampleDocument),
              ),
            ),
          ),
        ),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });
  });

  group('ReportExportResult handling', () {
    test('cancellation is represented without file path', () {
      const result = ReportExportResult(
        format: ReportExportFormat.csv,
        message: '\u062a\u0645 \u0625\u0644\u063a\u0627\u0621 \u0627\u0644\u062a\u0635\u062f\u064a\u0631',
      );
      expect(result.isSuccess, isFalse);
      expect(result.filePath, isNull);
      expect(result.message, isNotNull);
    });
  });
}

Widget _harness({
  required bool canExport,
  required void Function(BuildContext context, WidgetRef ref) onTrigger,
}) {
  return ProviderScope(
    overrides: [
      canExportReportsProvider.overrideWith((ref) => canExport),
    ],
    child: MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Consumer(
          builder: (context, ref, _) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => onTrigger(context, ref),
                child: const Text('trigger'),
              ),
            );
          },
        ),
      ),
    ),
  );
}

DashboardExportDocument _sampleDocument() {
  return DashboardExportDocument(
    title: '\u0644\u0648\u062d\u0629 \u0627\u0644\u0645\u0624\u0634\u0631\u0627\u062a \u0627\u0644\u0645\u0627\u0644\u064a\u0629',
    subtitle: 'sub',
    filterSummary: '\u0647\u0630\u0627 \u0627\u0644\u0634\u0647\u0631: 2026/03/01',
    generatedAt: DateTime(2026, 3, 1, 12, 0),
    sections: [
      const DashboardExportSection(
        kind: DashboardExportSectionKind.cashFlow,
        title: '\u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
        visible: true,
        kpis: [
          DashboardExportKpi(
            title: '\u0627\u0644\u0631\u0635\u064a\u062f \u0627\u0644\u0646\u0642\u062f\u064a',
            value: '1,000 \u062f.\u0639',
          ),
        ],
        charts: [
          DashboardExportChart(
            title: '\u0627\u062a\u062c\u0627\u0647 \u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
            kind: DashboardExportChartKind.trend,
            rows: [
              DashboardExportChartRow(
                label: '\u0627\u0644\u0627\u062b\u0646\u064a\u0646',
                primaryValue: '500 \u062f.\u0639',
                secondaryValue: '200 \u062f.\u0639',
              ),
            ],
          ),
        ],
      ),
      const DashboardExportSection(
        kind: DashboardExportSectionKind.supplementaryKpi,
        title: '\u0627\u0644\u0645\u0624\u0634\u0631\u0627\u062a \u0627\u0644\u062a\u0643\u0645\u064a\u0644\u064a\u0629',
        visible: true,
        kpis: [
          DashboardExportKpi(
            title: '\u0625\u062c\u0645\u0627\u0644\u064a \u0645\u0628\u064a\u0639\u0627\u062a \u0627\u0644\u0641\u062a\u0631\u0629',
            value: '9,000 \u062f.\u0639',
          ),
        ],
      ),
    ],
  );
}

DashboardExportDocument _emptyDocument() {
  return DashboardExportDocument(
    title: 't',
    subtitle: 's',
    filterSummary: 'f',
    generatedAt: DateTime(2026, 3, 1),
    sections: const [
      DashboardExportSection(
        kind: DashboardExportSectionKind.cashFlow,
        title: '\u0627\u0644\u062a\u062f\u0641\u0642 \u0627\u0644\u0646\u0642\u062f\u064a',
        visible: true,
      ),
    ],
  );
}