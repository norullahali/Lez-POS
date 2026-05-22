import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/providers/auth_provider.dart';
import '../../core/exports/report_export_models.dart';
import '../../core/exports/report_export_service.dart';
import '../../core/models/report_filter_model.dart';
import '../../core/providers/report_permissions.dart';
import 'analytics_export_formatter.dart';

class AnalyticsExportHelper {
  AnalyticsExportHelper._();

  static Future<void> exportCsv({
    required BuildContext context,
    required WidgetRef ref,
    required String reportId,
    required String titleAr,
    required ReportFilterModel filter,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    if (!ref.read(canExportReportsProvider)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية تصدير التقارير')),
      );
      return;
    }

    final user = ref.read(authProvider).valueOrNull?.user?.username;
    final result = await ReportExportService.export(
      ReportExportRequest(
        metadata: ReportExportMetadata(
          reportId: reportId,
          titleAr: titleAr,
          generatedAt: DateTime.now(),
          filterSummary: AnalyticsExportFormatter.filterSummary(filter),
          generatedBy: user,
        ),
        format: ReportExportFormat.csv,
        headers: headers,
        rows: rows,
      ),
    );
    if (!context.mounted) return;
    final msg = result.filePath != null
        ? 'تم حفظ التقرير: ${result.filePath}'
        : (result.message ?? 'تعذر التصدير');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}