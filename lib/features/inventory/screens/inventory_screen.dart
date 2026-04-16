// lib/features/inventory/screens/inventory_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_overlay.dart';
import '../../products/providers/products_provider.dart';
import '../providers/inventory_provider.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _nf = NumberFormat('#,##0.##');
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Column(
        children: [
          // Tab bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(icon: Icon(Icons.warehouse_rounded), text: 'نظرة عامة'),
                Tab(icon: Icon(Icons.warning_rounded), text: 'مخزون منخفض'),
                Tab(icon: Icon(Icons.schedule_rounded), text: 'تواريخ الانتهاء'),
                Tab(icon: Icon(Icons.tune_rounded), text: 'تسويات المخزن'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _StockOverviewTab(nf: _nf),
                _LowStockTab(nf: _nf),
                _ExpiryTab(nf: _nf),
                _AdjustmentsTab(nf: _nf, onAdjust: _showAdjustDialog),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdjustDialog(int productId, String productName, String unit) async {
    final qtyCtrl = TextEditingController();
    String adjustmentType = 'CORRECTION';
    final reasonCtrl = TextEditingController();
    bool isAddition = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('تسوية مخزن: $productName', textDirection: TextDirection.rtl),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: adjustmentType,
                decoration: const InputDecoration(labelText: 'نوع التسوية'),
                items: const [
                  DropdownMenuItem(value: 'CORRECTION', child: Text('تصحيح')),
                  DropdownMenuItem(value: 'DAMAGE', child: Text('تالف')),
                  DropdownMenuItem(value: 'LOSS', child: Text('فقدان')),
                ],
                onChanged: (v) => setStateDialog(() => adjustmentType = v ?? 'CORRECTION'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('نوع التغيير:'),
                const SizedBox(width: 12),
                ChoiceChip(label: const Text('إضافة'), selected: isAddition, onSelected: (_) => setStateDialog(() => isAddition = true)),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('خصم'), selected: !isAddition, onSelected: (_) => setStateDialog(() => isAddition = false)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, decoration: InputDecoration(labelText: 'الكمية ($unit)'), keyboardType: TextInputType.number, autofocus: true),
              const SizedBox(height: 12),
              TextField(controller: reasonCtrl, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'السبب'), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ التسوية')),
        ],
      )),
    );

    if (confirmed == true) {
      final qty = double.tryParse(qtyCtrl.text) ?? 0;
      if (qty <= 0) return;
      setState(() => _isLoading = true);
      try {
        await ref.read(inventoryNotifierProvider.notifier).adjust(
          productId: productId,
          quantityChange: isAddition ? qty : -qty,
          adjustmentType: adjustmentType,
          reason: reasonCtrl.text.trim(),
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت التسوية بنجاح'), backgroundColor: AppColors.success));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }
}

class _StockOverviewTab extends ConsumerWidget {
  final NumberFormat nf;
  const _StockOverviewTab({required this.nf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryNotifierProvider);
    return inventoryAsync.when(
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
            onPressed: () => ref.invalidate(inventoryNotifierProvider),
          ),
        ]),
      ),
      data: (items) {
        final totalValue = items.fold(0.0, (s, i) => s + i.stockValue);
        return Column(
          children: [
            // Summary card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                _MiniStat('إجمالي الأصناف', '${items.length}', AppColors.primary, Icons.inventory_2_rounded),
                const SizedBox(width: 12),
                _MiniStat('قيمة المخزون', '${NumberFormat('#,##0').format(totalValue)} د.ع', AppColors.success, Icons.attach_money_rounded),
                const SizedBox(width: 12),
                _MiniStat('مخزون منخفض', '${items.where((i) => i.isLowStock).length}', AppColors.warning, Icons.warning_rounded),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 12,
                      columns: const [
                        DataColumn(label: Text('المنتج')),
                        DataColumn(label: Text('الباركود')),
                        DataColumn(label: Text('المخزون'), numeric: true),
                        DataColumn(label: Text('الحد الأدنى'), numeric: true),
                        DataColumn(label: Text('سعر التكلفة'), numeric: true),
                        DataColumn(label: Text('القيمة الإجمالية'), numeric: true),
                      ],
                      rows: items.map((item) => DataRow(
                        color: WidgetStateProperty.all(item.isLowStock ? AppColors.errorLight : null),
                        cells: [
                          DataCell(Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(item.barcode.isEmpty ? '-' : item.barcode, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                          DataCell(Text('${nf.format(item.currentStock)} ${item.unit}', style: TextStyle(color: item.isLowStock ? AppColors.error : AppColors.success, fontWeight: FontWeight.w700))),
                          DataCell(Text(nf.format(item.minStock))),
                          DataCell(Text('${nf.format(item.costPrice)} د.ع')),
                          DataCell(Text('${NumberFormat('#,##0').format(item.stockValue)} د.ع', style: const TextStyle(fontWeight: FontWeight.w600))),
                        ],
                      )).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LowStockTab extends ConsumerWidget {
  final NumberFormat nf;
  const _LowStockTab({required this.nf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lowStockAsync = ref.watch(lowStockProvider);
    return lowStockAsync.when(
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
            onPressed: () => ref.invalidate(lowStockProvider),
          ),
        ]),
      ),
      data: (items) => items.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 64),
              SizedBox(height: 16),
              Text('لا توجد منتجات ذات مخزون منخفض', style: TextStyle(color: AppColors.success, fontSize: 16)),
            ]))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return ListTile(
                      leading: const CircleAvatar(backgroundColor: AppColors.errorLight, child: Icon(Icons.warning_rounded, color: AppColors.error, size: 20)),
                      title: Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('المخزون: ${nf.format(item['current_stock'])} / الحد: ${nf.format(item['min_stock'])}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.errorLight, borderRadius: BorderRadius.circular(20)),
                        child: const Text('منخفض', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _ExpiryTab extends ConsumerWidget {
  final NumberFormat nf;
  const _ExpiryTab({required this.nf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiryAsync = ref.watch(expiringProductsProvider);
    final df = DateFormat('yyyy/MM/dd');
    return expiryAsync.when(
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
            onPressed: () => ref.invalidate(expiringProductsProvider),
          ),
        ]),
      ),
      data: (items) => items.isEmpty
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 64),
              SizedBox(height: 16),
              Text('لا توجد منتجات قريبة الانتهاء', style: TextStyle(color: AppColors.success, fontSize: 16)),
            ]))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final expiryDate = item['expiry_date'] as DateTime?;
                    final daysLeft = expiryDate?.difference(DateTime.now()).inDays ?? 0;
                    final isExpired = daysLeft < 0;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isExpired ? AppColors.errorLight : AppColors.warningLight,
                        child: Icon(Icons.schedule_rounded, color: isExpired ? AppColors.error : AppColors.warning, size: 20),
                      ),
                      title: Text(item['product_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('تاريخ الانتهاء: ${expiryDate != null ? df.format(expiryDate) : '-'}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isExpired ? AppColors.errorLight : AppColors.warningLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(isExpired ? 'منتهي الصلاحية' : 'خلال $daysLeft يوم', style: TextStyle(color: isExpired ? AppColors.error : AppColors.warning, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _AdjustmentsTab extends ConsumerWidget {
  final NumberFormat nf;
  final Function(int, String, String) onAdjust;
  const _AdjustmentsTab({required this.nf, required this.onAdjust});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsNotifierProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('اختر منتجاً لإجراء تسوية المخزن', style: TextStyle(color: AppColors.textSecondary)),
                  ),
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
                      data: (products) => ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = products[i];
                          return ListTile(
                            leading: const Icon(Icons.inventory_2_outlined, color: AppColors.primary),
                            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('المخزون: ${nf.format(p.currentStock)} ${p.unit}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.tune_rounded, color: AppColors.primary),
                              onPressed: () => onAdjust(p.id!, p.name, p.unit),
                              tooltip: 'تسوية المخزن',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _MiniStat(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
            ]),
          ]),
        ),
      ),
    );
  }
}
