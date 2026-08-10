import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../providers/supplier_returns_list_provider.dart';
import 'widgets/create_supplier_return_dialog.dart';
import 'widgets/supplier_return_detail_dialog.dart';

class SupplierReturnsScreen extends ConsumerStatefulWidget {
  const SupplierReturnsScreen({super.key});

  @override
  ConsumerState<SupplierReturnsScreen> createState() =>
      _SupplierReturnsScreenState();
}

class _SupplierReturnsScreenState extends ConsumerState<SupplierReturnsScreen> {
  bool _createDialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final returnsAsync = ref.watch(supplierReturnsListProvider);
    final dateFmt = DateFormat('yyyy/MM/dd');
    final moneyFmt = NumberFormat('#,##0.##');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'مرتجعات الموردين',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'تحديث القائمة',
                onPressed: () => ref.invalidate(supplierReturnsListProvider),
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('مرتجع مورد'),
                onPressed:
                    _createDialogOpen ? null : _openCreateSupplierReturnDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'بحث برقم المرتجع أو المورد أو فاتورة الشراء',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: ref.watch(supplierReturnsSearchProvider).isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () => ref
                          .read(supplierReturnsSearchProvider.notifier)
                          .state = '',
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onChanged: (value) =>
                ref.read(supplierReturnsSearchProvider.notifier).state = value,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: returnsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'تعذر تحميل مرتجعات الموردين',
                      style: TextStyle(color: AppColors.error),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('إعادة المحاولة'),
                      onPressed: () =>
                          ref.invalidate(supplierReturnsListProvider),
                    ),
                  ],
                ),
              ),
              data: (returns) {
                if (returns.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_shipping_outlined,
                            size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text(
                          ref
                                  .watch(supplierReturnsSearchProvider)
                                  .trim()
                                  .isEmpty
                              ? 'لا توجد مرتجعات موردين'
                              : 'لا توجد نتائج مطابقة للبحث',
                          style: const TextStyle(color: AppColors.textHint),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  );
                }

                return Card(
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 16,
                      columns: const [
                        DataColumn(label: Text('رقم المرتجع')),
                        DataColumn(label: Text('فاتورة الشراء')),
                        DataColumn(label: Text('المورد')),
                        DataColumn(label: Text('التاريخ')),
                        DataColumn(label: Text('القيمة'), numeric: true),
                        DataColumn(label: Text('البنود'), numeric: true),
                        DataColumn(label: Text('الحالة')),
                        DataColumn(label: Text('')),
                      ],
                      rows: returns.map((item) {
                        return DataRow(
                          onSelectChanged: (_) =>
                              showSupplierReturnDetailDialog(
                            context,
                            ref,
                            item.id,
                          ),
                          cells: [
                            DataCell(Text(
                              item.displayReturnNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            )),
                            DataCell(Text(item.displayPurchaseInvoice)),
                            DataCell(Text(item.displaySupplierName)),
                            DataCell(Text(dateFmt.format(item.returnDate))),
                            DataCell(Text(
                              '${moneyFmt.format(item.total)} د.ع',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            )),
                            DataCell(Text('${item.lineCount}')),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: item.isPurchaseLinked
                                      ? AppColors.successLight
                                      : AppColors.warningLight,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  item.linkageLabel,
                                  style: TextStyle(
                                    color: item.isPurchaseLinked
                                        ? AppColors.success
                                        : AppColors.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'عرض التفاصيل',
                                icon: const Icon(Icons.visibility_outlined),
                                onPressed: () => showSupplierReturnDetailDialog(
                                  context,
                                  ref,
                                  item.id,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCreateSupplierReturnDialog() async {
    if (_createDialogOpen) return;
    setState(() => _createDialogOpen = true);
    final posted = await showCreateSupplierReturnDialog(context, ref);
    if (mounted) {
      setState(() => _createDialogOpen = false);
      if (posted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم حفظ مرتجع المورد بنجاح',
              textDirection: TextDirection.rtl,
            ),
          ),
        );
      }
    }
  }
}
