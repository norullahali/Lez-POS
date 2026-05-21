import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import 'activity_category_chip.dart';
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
    final absolute = DateFormat('EEEE، d MMMM yyyy — HH:mm:ss', 'ar').format(log.createdAt);
    final relative = _relativeAr(log.createdAt);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      log.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActivitySeverityChip(severity: log.severity, showIcon: true),
                  ActivityCategoryChip(category: log.category),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                absolute,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              Text(
                relative,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row('الإجراء', log.action),
                      _row('المستخدم', log.usernameSnapshot ?? '—'),
                      _row('الدور', log.roleSnapshot ?? '—'),
                      if (log.sessionId != null) _row('الجلسة', '#${log.sessionId}'),
                      if (log.entityType != null)
                        _row('الكيان', '${log.entityType} #${log.entityId ?? '—'}'),
                      if (log.routeContext != null) _row('المسار', log.routeContext!),
                      if (log.description != null) _row('الوصف', log.description!),
                      if (log.beforeJson != null && log.afterJson != null)
                        _CompareJsonSection(beforeRaw: log.beforeJson!, afterRaw: log.afterJson!)
                      else ...[
                        if (log.beforeJson != null)
                          _ExpandableJsonSection(title: 'قبل', raw: log.beforeJson!),
                        if (log.afterJson != null)
                          _ExpandableJsonSection(title: 'بعد', raw: log.afterJson!),
                      ],
                      if (log.metadataJson != null)
                        _ExpandableJsonSection(title: 'بيانات إضافية', raw: log.metadataJson!),
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

  static String _relativeAr(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'منذ لحظات';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inDays < 1) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
    return DateFormat('yyyy/MM/dd').format(dt);
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _CompareJsonSection extends StatelessWidget {
  const _CompareJsonSection({required this.beforeRaw, required this.afterRaw});
  final String beforeRaw;
  final String afterRaw;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('مقارنة قبل / بعد', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _JsonPanel(title: 'قبل', raw: beforeRaw, accent: AppColors.warning)),
              const SizedBox(width: 10),
              Expanded(child: _JsonPanel(title: 'بعد', raw: afterRaw, accent: AppColors.success)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpandableJsonSection extends StatelessWidget {
  const _ExpandableJsonSection({required this.title, required this.raw});
  final String title;
  final String raw;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        children: [
          _JsonPanel(title: title, raw: raw, accent: AppColors.info, expanded: true),
        ],
      ),
    );
  }
}

class _JsonPanel extends StatelessWidget {
  const _JsonPanel({
    required this.title,
    required this.raw,
    required this.accent,
    this.expanded = false,
  });

  final String title;
  final String raw;
  final Color accent;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final pretty = _prettyJson(raw);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: accent, fontSize: 12)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () => _copy(context, pretty),
              ),
            ],
          ),
          SelectableText(
            pretty,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.45),
            maxLines: expanded ? null : 8,
          ),
        ],
      ),
    );
  }
}

String _prettyJson(String raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw;
  }
}

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('تم النسخ'), duration: Duration(seconds: 2)),
  );
}