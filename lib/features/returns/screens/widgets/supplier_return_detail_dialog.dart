// lib/features/returns/screens/widgets/supplier_return_detail_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../providers/supplier_returns_list_provider.dart';

Future<void> showSupplierReturnDetailDialog(
  BuildContext context,
  WidgetRef ref,
  int returnId,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => SupplierReturnDetailDialog(returnId: returnId),
  );
}

class SupplierReturnDetailDialog extends ConsumerWidget {
  const SupplierReturnDetailDialog({super.key, required this.returnId});

  final int returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(supplierReturnDetailProvider(returnId));
    final dateFmt = DateFormat('yyyy/MM/dd HH:mm');
    final moneyFmt = NumberFormat('#,##0.##');

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 640),
        child: detailAsync.when(
          loading: () => const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 40),
                const SizedBox(height: 12),
                const Text('تعذر تحميل تفاصيل المرتجع',
                    textDirection: TextDirection.rtl),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
          data: (detail) {
            if (detail == null) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('المرتجع غير موجود',
                        textDirection: TextDirection.rtl),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إغلاق'),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'تفاصيل مرتجع ${detail.displayReturnNumber}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    textDirection: TextDirection.rtl,
                    children: [
                      _MetaChip(
                          label: 'المورد', value: detail.displaySupplierName),
                      _MetaChip(
                          label: 'فاتورة الشراء',
                          value: detail.displayPurchaseInvoice),
                      _MetaChip(
                          label: 'التاريخ',
                          value: dateFmt.format(detail.returnDate)),
                      _MetaChip(
                          label: 'الإجمالي',
                          value: '${moneyFmt.format(detail.total)} د.ع'),
                    ],
                  ),
                ),
                if (detail.reason.isNotEmpty || detail.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (detail.reason.isNotEmpty)
                          Text('السبب: ${detail.reason}',
                              textDirection: TextDirection.rtl),
                        if (detail.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('ملاحظات: ${detail.notes}',
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                    color: AppColors.textSecondary)),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('البنود المرجعة',
                      style: TextStyle(fontWeight: FontWeight.w700),
                      textDirection: TextDirection.rtl),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 16,
                        columns: const [
                          DataColumn(label: Text('المنتج')),
                          DataColumn(label: Text('الكمية'), numeric: true),
                          DataColumn(label: Text('التكلفة'), numeric: true),
                          DataColumn(label: Text('الإجمالي'), numeric: true),
                        ],
                        rows: detail.lines.map((line) {
                          return DataRow(cells: [
                            DataCell(Text(line.productName)),
                            DataCell(Text(moneyFmt.format(line.quantity))),
                            DataCell(Text(moneyFmt.format(line.unitCost))),
                            DataCell(Text(moneyFmt.format(line.total))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            textDirection: TextDirection.rtl),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textDirection: TextDirection.rtl),
      ],
    );
  }
}
