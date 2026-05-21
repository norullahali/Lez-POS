import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/activity/activity_categories.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import 'activity_severity_chip.dart';

Future<void> showActivityLogDetailDialog(BuildContext context, ActivityLog log) {
  return showDialog(
    context: context,
    builder: (_) => ActivityLogDetailDialog(log: log),
  );
}

class ActivityLogDetailDialog extends StatelessWidget {
  const ActivityLogDetailDialog({super.key, required this.log});
  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final ts = DateFormat('yyyy/MM/dd HH:mm:ss').format(log.createdAt);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(log.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  ActivitySeverityChip(severity: log.severity),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 8),
              Text(ts, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row('الفئة', ActivityCategories.labelAr(log.category)),
                      _row('الإجراء', log.action),
                      _row('المستخدم', log.usernameSnapshot ?? '-'),
                      _row('الدور', log.roleSnapshot ?? '-'),
                      if (log.entityType != null) _row('الكيان', '${log.entityType} #${log.entityId ?? '-'}'),
                      if (log.description != null) _row('الوصف', log.description!),
                      if (log.beforeJson != null) _jsonBlock('قبل', log.beforeJson!),
                      if (log.afterJson != null) _jsonBlock('بعد', log.afterJson!),
                      if (log.metadataJson != null) _jsonBlock('بيانات إضافية', log.metadataJson!),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _jsonBlock(String label, String raw) {
    String pretty = raw;
    try {
      pretty = const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(pretty, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ],
      ),
    );
  }
}