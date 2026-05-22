import 'package:intl/intl.dart';

enum ReportExportFormat { csv, pdf, excel, printPreview }

class ReportExportMetadata {
  const ReportExportMetadata({
    required this.reportId,
    required this.titleAr,
    required this.generatedAt,
    this.filterSummary,
    this.generatedBy,
    this.formatVersion = '1.0',
  });

  final String reportId;
  final String titleAr;
  final DateTime generatedAt;
  final String? filterSummary;
  final String? generatedBy;
  final String formatVersion;

  static final _fileStamp = DateFormat('yyyyMMdd_HHmmss');
  static final _displayStamp = DateFormat('yyyy/MM/dd HH:mm');

  /// Standard filename: `{reportId}_{timestamp}.csv`
  String buildFileName(ReportExportFormat format) {
    final ext = switch (format) {
      ReportExportFormat.csv => 'csv',
      ReportExportFormat.pdf => 'pdf',
      ReportExportFormat.excel => 'xlsx',
      ReportExportFormat.printPreview => 'txt',
    };
    return '${reportId}_${_fileStamp.format(generatedAt)}.$ext';
  }

  /// Metadata header lines for CSV (comment-prefixed, Arabic-safe).
  List<String> headerLines() {
    return [
      '# $titleAr',
      if (filterSummary != null) '# الفلاتر: $filterSummary',
      '# تاريخ التوليد: ${_displayStamp.format(generatedAt)}',
      if (generatedBy != null) '# بواسطة: $generatedBy',
      '# الإصدار: $formatVersion',
    ];
  }
}

class ReportExportRequest {
  const ReportExportRequest({
    required this.metadata,
    required this.format,
    required this.headers,
    required this.rows,
  });

  final ReportExportMetadata metadata;
  final ReportExportFormat format;
  final List<String> headers;
  final List<List<String>> rows;
}

class ReportExportResult {
  const ReportExportResult({
    required this.format,
    this.filePath,
    this.message,
  });

  final ReportExportFormat format;
  final String? filePath;
  final String? message;

  bool get isSuccess => filePath != null;
}
