import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../auth/providers/auth_provider.dart';
import '../../reports/core/exports/report_export_models.dart';
import '../../reports/core/exports/report_export_service.dart';
import '../models/cash_ledger_event.dart';
import '../providers/cash_ledger_filter_provider.dart';
import '../providers/cash_ledger_providers.dart';
import '../../reports/modules/shared/analytics_formatters.dart';

class CashLedgerExportHelper {
  CashLedgerExportHelper._();

  static Future<void> exportCsv(BuildContext context, WidgetRef ref) async {
    final filter = ref.read(cashLedgerFilterProvider);
    final repo = ref.read(financialLedgerRepositoryProvider);
    final entries = await repo.getEntriesForExport(filter);
    if (!context.mounted) return;

    final user = ref.read(authProvider).valueOrNull?.user?.fullName;
    final df = DateFormat('yyyy/MM/dd HH:mm');

    final result = await ReportExportService.export(
      ReportExportRequest(
        metadata: ReportExportMetadata(
          reportId: 'cash_ledger',
          titleAr: 'دفتر النقدية',
          generatedAt: DateTime.now(),
          filterSummary: filter.dateFilter.summaryAr(),
          generatedBy: user,
          formatVersion: '1.0',
        ),
        format: ReportExportFormat.csv,
        headers: const [
          'التاريخ',
          'النوع',
          'المرجع',
          'الوصف',
          'وارد',
          'صادر',
          'الرصيد التراكمي',
        ],
        rows: entries
            .map((e) => _row(e, df))
            .toList(),
      ),
    );

    if (!context.mounted) return;
    final msg = result.isSuccess
        ? 'تم حفظ الملف: ${result.filePath}'
        : (result.message ?? 'تعذر التصدير');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static List<String> _row(CashLedgerEvent e, DateFormat df) {
    return [
      df.format(e.timestamp),
      e.eventType.labelAr,
      '${e.referenceType}#${e.referenceId}',
      e.description,
      e.isInflow ? AnalyticsFormatters.currency.format(e.amount) : '',
      e.isInflow ? '' : AnalyticsFormatters.currency.format(e.amount),
      e.runningBalance != null
          ? AnalyticsFormatters.currency.format(e.runningBalance!)
          : '',
    ];
  }
}