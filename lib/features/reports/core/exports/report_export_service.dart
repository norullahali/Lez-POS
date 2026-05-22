import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'report_export_models.dart';

/// Base export engine — currently implements CSV; PDF/Excel/print are future-ready.
class ReportExportService {
  ReportExportService._();

  static Future<ReportExportResult> export(ReportExportRequest request) async {
    switch (request.format) {
      case ReportExportFormat.csv:
        return _exportCsv(request);
      case ReportExportFormat.pdf:
      case ReportExportFormat.excel:
      case ReportExportFormat.printPreview:
        return ReportExportResult(
          format: request.format,
          message: 'التصدير بصيغة ${request.format.name} سيتوفر قريباً',
        );
    }
  }

  static Future<ReportExportResult> _exportCsv(ReportExportRequest request) async {
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM for Excel Arabic support

    for (final line in request.metadata.headerLines()) {
      buffer.writeln(line);
    }
    buffer.writeln('');

    buffer.writeln(request.headers.map(_escapeCsv).join(','));
    for (final row in request.rows) {
      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    final defaultName = request.metadata.buildFileName(ReportExportFormat.csv);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'حفظ التقرير',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );

    if (path == null) {
      return const ReportExportResult(
        format: ReportExportFormat.csv,
        message: 'تم إلغاء التصدير',
      );
    }

    final filePath = path.toLowerCase().endsWith('.csv') ? path : '$path.csv';
    await File(filePath).writeAsBytes(utf8.encode(buffer.toString()));

    return ReportExportResult(format: ReportExportFormat.csv, filePath: filePath);
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
