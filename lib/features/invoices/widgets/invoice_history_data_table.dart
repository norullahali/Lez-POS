import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../models/invoice_history_row.dart';

typedef InvoiceRowOpenCallback = void Function(int invoiceId);

class InvoiceHistoryDataTable extends StatelessWidget {
  final List<InvoiceHistoryRow> rows;
  final NumberFormat nf;
  final InvoiceRowOpenCallback onOpenInvoice;

  const InvoiceHistoryDataTable({
    super.key,
    required this.rows,
    required this.nf,
    required this.onOpenInvoice,
  });

  static final _df = DateFormat('yyyy/MM/dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final baseText = Theme.of(context).textTheme.bodyMedium;
    final headingStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppColors.primarySurface),
              dataRowMinHeight: 44,
              dataRowMaxHeight: 52,
              columnSpacing: 28,
              horizontalMargin: 20,
              columns: [
                DataColumn(
                  label: Text('رقم الفاتورة', style: headingStyle),
                ),
                DataColumn(
                  label: Text('التاريخ', style: headingStyle),
                ),
                DataColumn(
                  label: Text('العميل', style: headingStyle),
                ),
                DataColumn(
                  label: Text('الكاشير', style: headingStyle),
                ),
                DataColumn(
                  label: Text('الأصناف', style: headingStyle),
                ),
                DataColumn(
                  label: Text('الإجمالي', style: headingStyle),
                ),
                DataColumn(
                  label: Text('الدفع', style: headingStyle),
                ),
                DataColumn(
                  label: Text('الحالة', style: headingStyle),
                ),
              ],
              rows: [
                for (var i = 0; i < rows.length; i++)
                  DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.hovered)) {
                        return AppColors.surfaceVariant
                            .withValues(alpha: 0.85);
                      }
                      if (i.isEven) {
                        return AppColors.surfaceVariant.withValues(alpha: 0.35);
                      }
                      return null;
                    }),
                    onSelectChanged: (_) => onOpenInvoice(rows[i].id),
                    cells: [
                      DataCell(Text(rows[i].invoiceNumber, style: baseText)),
                      DataCell(Text(_df.format(rows[i].saleDate), style: baseText)),
                      DataCell(Text(rows[i].customerName, style: baseText)),
                      DataCell(Text(rows[i].cashierName, style: baseText)),
                      DataCell(Text('${rows[i].itemCount}', style: baseText)),
                      DataCell(Text('${nf.format(rows[i].total)} د.ع',
                          style: baseText)),
                      DataCell(Text(
                        invoicePaymentLabelAr(rows[i].paymentMethod),
                        style: baseText,
                      )),
                      DataCell(Text(rows[i].status, style: baseText)),
                    ],
                  ),
              ],
            ),
          ),
        ),
    );
  }
}
