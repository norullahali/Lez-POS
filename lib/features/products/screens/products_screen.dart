// lib/features/products/screens/products_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/search_field.dart';
import '../../categories/providers/categories_provider.dart';
import '../models/product_model.dart';
import '../providers/products_provider.dart';
import 'widgets/product_form_dialog.dart';

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsNotifierProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Toolbar
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SearchField(
                  hint: 'ابحث بالاسم أو الباركود...',
                  onChanged: (q) => ref.read(productsNotifierProvider.notifier).search(q),
                ),
              ),
              const SizedBox(width: 12),
              // Category filter
              categoriesAsync.when(
                data: (cats) => DropdownButton<int?>(
                  hint: const Text('كل الفئات'),
                  value: null,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('كل الفئات')),
                    ...cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                  ],
                  onChanged: (id) => ref.read(productsNotifierProvider.notifier).filterByCategory(id),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('إضافة منتج'),
                onPressed: () => _showForm(context, ref, null),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Table
          Expanded(
            child: productsAsync.when(
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
                    onPressed: () => ref.invalidate(productsNotifierProvider),
                  ),
                ]),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('لا توجد منتجات', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة أول منتج'),
                          onPressed: () => _showForm(context, ref, null),
                        ),
                      ],
                    ),
                  );
                }
                return Card(
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 16,
                      headingRowHeight: 48,
                      dataRowMaxHeight: 56,
                      columns: const [
                        DataColumn(label: Text('المنتج')),
                        DataColumn(label: Text('الباركود')),
                        DataColumn(label: Text('الفئة')),
                        DataColumn(label: Text('سعر البيع'), numeric: true),
                        DataColumn(label: Text('المخزون'), numeric: true),
                        DataColumn(label: Text('الحالة')),
                        DataColumn(label: Text('إجراءات')),
                      ],
                      rows: products.map((p) => _buildRow(context, ref, p)).toList(),
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

  DataRow _buildRow(BuildContext context, WidgetRef ref, ProductModel p) {
    final isLow = p.currentStock <= p.minStock && p.minStock > 0;
    return DataRow(cells: [
      DataCell(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(p.unit, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
      DataCell(Text(p.barcode.isEmpty ? '-' : p.barcode, style: const TextStyle(fontFamily: 'monospace'))),
      DataCell(Text(p.categoryName ?? '-')),
      DataCell(Text('${p.sellPrice.toStringAsFixed(0)} د.ع')),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isLow ? AppColors.errorLight : AppColors.successLight,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            p.currentStock.toStringAsFixed(1),
            style: TextStyle(color: isLow ? AppColors.error : AppColors.success, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
      DataCell(
        Switch.adaptive(
          value: p.isActive,
          activeTrackColor: AppColors.success,
          onChanged: (val) => ref.read(productsNotifierProvider.notifier).toggle(p.id!, val),
        ),
      ),
      DataCell(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit_rounded, color: AppColors.primary, size: 20), onPressed: () => _showForm(context, ref, p), tooltip: 'تعديل'),
        ],
      )),
    ]);
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref, ProductModel? existing) async {
    final result = await showDialog<ProductModel>(context: context, builder: (_) => ProductFormDialog(existing: existing));
    if (result != null) {
      final notifier = ref.read(productsNotifierProvider.notifier);
      if (existing == null) {
        await notifier.add(result);
      } else {
        await notifier.updateProduct(result);
      }
    }
  }
}
