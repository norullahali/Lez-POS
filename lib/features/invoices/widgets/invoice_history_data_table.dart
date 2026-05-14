import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../models/invoice_history_row.dart';

class InvoiceHistoryDataTable extends StatelessWidget {
  final List<InvoiceHistoryRow> rows;
  final NumberFormat nf;
  final DateFormat df;

  const InvoiceHistoryDataTable({
    super.key,
    required this.rows,
    required this.nf,
    required this.df,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 13,
        );

    DataRow buildRow(InvoiceHistoryRow r, int i) {
      return DataRow(
        color: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.hovered)) {
            return AppColors.primary.withValues(alpha: 0.06);
          }
          return i.isEven
              ? Colors.grey.shade50
              : Colors.white;
        }),
        cells: [
          DataCell(Text(r.invoiceNumber, style: baseStyle)),
          DataCell(Text(df.format(r.saleDate), style: baseStyle)),
          DataCell(Text(r.customerName, style: baseStyle)),
          DataCell(Text(r.cashierName, style: baseStyle)),
          DataCell(Text(nf.format(r.itemCount), style: baseStyle)),
          DataCell(Text('${nf.format(r.total)} د.ع', style: baseStyle)),
          DataCell(
              Text(invoicePaymentLabelAr(r.paymentMethod), style: baseStyle)),
          DataCell(Text(r.status, style: baseStyle)),
        ],
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: true,
        physics: const AlwaysScrollableScrollPhysics(),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              AppColors.primary.withValues(alpha: 0.12),
            ),
            horizontalMargin: 20,
            columnSpacing: 28,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            headingTextStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
            columns: const [
              DataColumn(label: Text('رقم الفاتورة')),
              DataColumn(label: Text('التاريخ والوقت')),
              DataColumn(label: Text('العميل')),
              DataColumn(label: Text('الكاشير')),
              DataColumn(label: Text('عدد الأصناف')),
              DataColumn(label: Text('الإجمالي')),
              DataColumn(label: Text('طريقة الدفع')),
              DataColumn(label: Text('الحالة')),
            ],
            rows: List.generate(rows.length, (i) => buildRow(rows[i], i)),
          ),
        ),
      ),
    );
  }
}
