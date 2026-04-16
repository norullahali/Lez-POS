// lib/features/opening_stock/screens/opening_stock_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/loading_overlay.dart';
import '../../products/providers/products_provider.dart';
import '../providers/opening_stock_provider.dart';

class OpeningStockScreen extends ConsumerStatefulWidget {
  const OpeningStockScreen({super.key});

  @override
  ConsumerState<OpeningStockScreen> createState() => _OpeningStockScreenState();
}

class _OpeningStockScreenState extends ConsumerState<OpeningStockScreen> {
  final _searchCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(openingStockNotifierProvider);
    final productsAsync = ref.watch(productsNotifierProvider);
    final nf = NumberFormat('#,##0.##');

    return LoadingOverlay(
      isLoading: _isSaving,
      message: 'جاري حفظ الرصيد الافتتاحي...',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.infoLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.info.withValues(alpha: 0.3))),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.info),
                  const SizedBox(width: 12),
                  Expanded(child: Text('استخدم هذه الشاشة لإدخال الكميات الحالية للمنتجات عند بدء استخدام النظام لأول مرة. سيتم حفظ الكميات كرصيد افتتاحي في المخزن.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.info))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(hintText: 'اضغط على منتج لإضافته...', prefixIcon: Icon(Icons.search_rounded)),
                    onChanged: (q) => ref.read(productsNotifierProvider.notifier).search(q),
                  ),
                ),
                const SizedBox(width: 16),
                if (entries.isNotEmpty)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: Text('حفظ الرصيد (${entries.length})'),
                    onPressed: _confirmSave,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product picker
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: Column(
                        children: [
                          Container(padding: const EdgeInsets.all(12), child: Text('المنتجات المتاحة', style: Theme.of(context).textTheme.titleSmall)),
                          Expanded(
                            child: productsAsync.when(
                              loading: () => const Center(child: CircularProgressIndicator()),
                              error: (e, _) => Center(child: Text('خطأ: $e')),
                              data: (products) => ListView.separated(
                                itemCount: products.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final p = products[i];
                                  final isAdded = entries.any((e) => e.productId == p.id);
                                  return ListTile(
                                    dense: true,
                                    title: Text(p.name, style: TextStyle(fontWeight: isAdded ? FontWeight.w700 : FontWeight.w400, color: isAdded ? AppColors.primary : null)),
                                    subtitle: Text('المخزون الحالي: ${p.currentStock.toStringAsFixed(1)} ${p.unit}'),
                                    trailing: isAdded ? const Icon(Icons.check_circle_rounded, color: AppColors.success) : const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                                    onTap: () => _showAddDialog(p.id!, p.name, p.unit, p.costPrice),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Entries list
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Text('الرصيد الافتتاحي (${entries.length})', style: Theme.of(context).textTheme.titleSmall),
                                const Spacer(),
                                if (entries.isNotEmpty)
                                  TextButton.icon(
                                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                                    label: const Text('مسح الكل'),
                                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                                    onPressed: () => ref.read(openingStockNotifierProvider.notifier).clear(),
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: entries.isEmpty
                                ? const Center(child: Text('لم تُضف أي منتجات بعد', style: TextStyle(color: AppColors.textHint)))
                                : ListView.separated(
                                    itemCount: entries.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final e = entries[i];
                                      return ListTile(
                                        title: Text(e.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        subtitle: Text('${nf.format(e.quantity)} ${e.productUnit}'),
                                        trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18), onPressed: () => ref.read(openingStockNotifierProvider.notifier).removeEntry(e.productId)),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// تحويل الأرقام العربية والشرقية إلى أرقام لاتينية
  static String _normalizeNumber(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const arabic = '۰۱۲۳۴۵۶۷۸۹';
    var result = input;
    for (int i = 0; i < 10; i++) {
      result = result
          .replaceAll(eastern[i], '$i')
          .replaceAll(arabic[i], '$i');
    }
    return result;
  }

  Future<void> _showAddDialog(int productId, String productName, String unit, double cost) async {
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(text: cost.toStringAsFixed(2));

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: Text('رصيد: $productName', textDirection: TextDirection.rtl),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyCtrl,
                decoration: InputDecoration(labelText: 'الكمية ($unit)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: costCtrl,
                decoration: const InputDecoration(labelText: 'سعر التكلفة'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      );

      if (result == true && mounted) {
        final qty = double.tryParse(_normalizeNumber(qtyCtrl.text.trim())) ?? 1;
        final unitCost = double.tryParse(_normalizeNumber(costCtrl.text.trim())) ?? cost;
        ref.read(openingStockNotifierProvider.notifier).addEntry(OpeningStockEntry(
          productId: productId,
          productName: productName,
          productUnit: unit,
          quantity: qty,
          unitCost: unitCost,
        ));
      }
    } finally {
      qtyCtrl.dispose();
      costCtrl.dispose();
    }
  }

  Future<void> _confirmSave() async {
    final confirmed = await ConfirmationDialog.show(
      context,
      title: 'حفظ الرصيد الافتتاحي',
      message: 'هل تريد حفظ الرصيد الافتتاحي لـ ${ref.read(openingStockNotifierProvider).length} منتج؟ سيتم تحديث المخزون.',
      confirmLabel: 'حفظ',
      confirmColor: AppColors.success,
    );
    if (!confirmed) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(openingStockNotifierProvider.notifier).save();
      ref.invalidate(productsNotifierProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الرصيد الافتتاحي بنجاح'), backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
