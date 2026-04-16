// lib/features/purchases/screens/purchases_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../providers/purchases_provider.dart';

class PurchasesListScreen extends ConsumerWidget {
  const PurchasesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(purchasesStreamProvider);
    final nf = NumberFormat('#,##0');
    final df = DateFormat('yyyy/MM/dd');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('فاتورة شراء جديدة'),
                onPressed: () {
                  ref.read(purchaseFormProvider.notifier).reset();
                  context.go('/purchases/new');
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: invoicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text('خطأ: $e', style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                    onPressed: () => ref.invalidate(purchasesStreamProvider),
                  ),
                ]),
              ),
              data: (invoices) {
                if (invoices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('لا توجد فواتير شراء', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('إنشاء أول فاتورة'),
                          onPressed: () {
                            ref.read(purchaseFormProvider.notifier).reset();
                            context.go('/purchases/new');
                          },
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
                        DataColumn(label: Text('رقم الفاتورة')),
                        DataColumn(label: Text('المورد')),
                        DataColumn(label: Text('التاريخ')),
                        DataColumn(label: Text('الإجمالي'), numeric: true),
                        DataColumn(label: Text('الحالة')),
                      ],
                      rows: invoices.map((inv) {
                        return DataRow(cells: [
                          DataCell(Text(inv.invoiceNumber.isEmpty ? '#${inv.id}' : inv.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
                          DataCell(Text(inv.supplierName ?? 'غير محدد')),
                          DataCell(Text(df.format(inv.purchaseDate))),
                          DataCell(Text('${nf.format(inv.total)} د.ع', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary))),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('مؤكد', style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
                          )),
                        ]);
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
}
