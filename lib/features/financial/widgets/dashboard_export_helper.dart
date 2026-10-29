import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../reports/core/exports/report_export_models.dart';
import '../../reports/core/exports/report_export_service.dart';
import '../../reports/core/providers/report_permissions.dart';
import '../models/dashboard_export.dart';
import 'dashboard_export_csv_mapper.dart';

/// CSV and clipboard export for the Financial Dashboard (B42 Stage 1).
class DashboardExportHelper {
  DashboardExportHelper._();

  static const _deniedMessage =
      '\u0644\u064a\u0633 \u0644\u062f\u064a\u0643 \u0635\u0644\u0627\u062d\u064a\u0629 \u062a\u0635\u062f\u064a\u0631 \u0627\u0644\u062a\u0642\u0627\u0631\u064a\u0631';

  static const _emptyMessage =
      '\u0644\u0627 \u062a\u0648\u062c\u062f \u0628\u064a\u0627\u0646\u0627\u062a \u0644\u0644\u062a\u0635\u062f\u064a\u0631. \u062d\u062f\u0651\u0650\u062b \u0627\u0644\u0644\u0648\u062d\u0629 \u062b\u0645 \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649.';

  static const _writeFailureMessage =
      '\u062a\u0639\u0630\u0651\u0631 \u062d\u0641\u0652\u0638 \u0627\u0644\u0645\u0644\u0641';

  static const _copyEmptyMessage =
      '\u0644\u0627 \u064a\u0648\u062c\u062f \u0645\u0644\u062e\u0635 \u0644\u0644\u0646\u0633\u062e';

  static const _copySuccessMessage =
      '\u062a\u0645 \u0646\u0633\u062e \u0627\u0644\u0645\u0644\u062e\u0635';

  static bool canExport(WidgetRef ref) => ref.read(canExportReportsProvider);

  static Future<void> exportCsv({
    required BuildContext context,
    required WidgetRef ref,
    required DashboardExportDocument document,
  }) async {
    if (!canExport(ref)) {
      _showSnackBar(context, _deniedMessage);
      return;
    }
    if (!document.hasExportableContent) {
      _showSnackBar(context, _emptyMessage);
      return;
    }

    final user = ref.read(authProvider).valueOrNull?.user?.username;
    final request = DashboardExportCsvMapper.toRequest(
      document,
      generatedBy: user,
    );

    ReportExportResult result;
    try {
      result = await ReportExportService.export(request);
    } catch (e, st) {
      debugPrint('[DashboardExportHelper] exportCsv failed: $e\n$st');
      if (!context.mounted) return;
      _showSnackBar(context, _writeFailureMessage);
      return;
    }

    if (!context.mounted) return;
    final msg = result.filePath != null
        ? '\u062a\u0645 \u062d\u0641\u0638 \u0627\u0644\u0645\u0644\u0641: ${result.filePath}'
        : (result.message ?? _writeFailureMessage);
    _showSnackBar(context, msg);
  }

  static Future<void> copySummary({
    required BuildContext context,
    required WidgetRef ref,
    required DashboardExportDocument document,
  }) async {
    if (!canExport(ref)) {
      _showSnackBar(context, _deniedMessage);
      return;
    }
    if (!document.hasExportableContent) {
      _showSnackBar(context, _emptyMessage);
      return;
    }

    final text = document.toPlainTextSummary().trim();
    if (text.isEmpty) {
      _showSnackBar(context, _copyEmptyMessage);
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    _showSnackBar(context, _copySuccessMessage);
  }

  static void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}