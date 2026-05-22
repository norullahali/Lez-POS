import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import 'report_empty_view.dart';

class ReportTableHeader extends StatelessWidget {
  const ReportTableHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class ReportTableEmptyState extends StatelessWidget {
  const ReportTableEmptyState({super.key, required this.message, this.icon = Icons.table_rows_rounded});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: ReportEmptyView(icon: icon, message: message),
    );
  }
}

class ReportTableCard extends StatelessWidget {
  const ReportTableCard({
    super.key,
    this.title,
    this.subtitle,
    required this.columns,
    required this.rows,
    this.isEmpty = false,
    this.emptyMessage = 'لا توجد بيانات',
    this.emptyIcon = Icons.table_rows_rounded,
    this.scrollable = true,
  });

  final String? title;
  final String? subtitle;
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final bool isEmpty;
  final String emptyMessage;
  final IconData emptyIcon;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final table = DataTable(
      columnSpacing: 16,
      headingRowHeight: 44,
      dataRowMinHeight: 44,
      dataRowMaxHeight: 64,
      columns: columns,
      rows: rows,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ReportTableHeader(title: title!, subtitle: subtitle),
          if (title != null) const Divider(height: 1),
          if (isEmpty)
            ReportTableEmptyState(message: emptyMessage, icon: emptyIcon)
          else if (scrollable)
            SingleChildScrollView(child: table)
          else
            table,
        ],
      ),
    );
  }
}