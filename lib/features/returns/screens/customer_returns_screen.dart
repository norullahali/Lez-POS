import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_overlay.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/pos_sale_service.dart';
import '../../../core/widgets/manager_approval_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../../products/providers/products_provider.dart';

final customerReturnsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = AppDatabase.instance;
  final rows = await db.customSelect(
    '''SELECT cr.*, si.invoice_number as sale_invoice_number
       FROM customer_returns cr
       LEFT JOIN sales_invoices si ON si.id = cr.original_invoice_id
       ORDER BY cr.return_date DESC LIMIT 100''',
    readsFrom: {db.customerReturns, db.salesInvoices},
  ).get();
  return rows.map((r) => r.data).toList();
});

class CustomerReturnsScreen extends ConsumerStatefulWidget {
  const CustomerReturnsScreen({super.key});

  @override
  ConsumerState<CustomerReturnsScreen> createState() => _CustomerReturnsScreenState();
}

class _CustomerReturnsScreenState extends ConsumerState<CustomerReturnsScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final returnsAsync = ref.watch(customerReturnsProvider);
    
    return LoadingOverlay(
      isLoading: _isLoading,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(children: [
              const Text('مرتجعات العملاء', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary)),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.flash_on_rounded, size: 18), 
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
                label: const Text('استرجاع بدون فاتورة'), 
                onPressed: _showQuickReturnDialog
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18), 
                label: const Text('مرتجع جديد'), 
                onPressed: _showCustomerReturnDialog
              ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: returnsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (returns) => returns.isEmpty
                    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.assignment_return_outlined, size: 64, color: AppColors.textHint),
                        SizedBox(height: 16),
                        Text('لا توجد مرتجعات عملاء', style: TextStyle(color: AppColors.textHint)),
                      ]))
                    : Card(
                        child: ListView.separated(
                          itemCount: returns.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = returns[i];
                            return ListTile(
                              leading: const CircleAvatar(backgroundColor: AppColors.warningLight, child: Icon(Icons.assignment_return_rounded, color: AppColors.warning)),
                              title: Text(r['return_number'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('فاتورة: ${r['sale_invoice_number'] ?? 'غير محدد'}'),
                              trailing: Text(r['reason'] as String? ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomerReturnDialog() async {
    final invoiceCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    int? selectedProductId;
    String selectedUnit = 'قطعة';
    final qtyCtrl = TextEditingController(text: '1');
    final products = await ref.read(productsRepositoryProvider).getAll();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setStateDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('مرتجع عميل جديد', textDirection: TextDirection.rtl),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: invoiceCtrl, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'رقم الفاتورة الأصلية (اختياري)')),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: selectedProductId,
                decoration: const InputDecoration(labelText: 'المنتج *'),
                items: [const DropdownMenuItem(value: null, child: Text('اختر منتجاً')), ...products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))],
                onChanged: (v) => setStateDialog(() {
                  selectedProductId = v;
                  if (v != null) {
                    final p = products.firstWhere((pr) => pr.id == v);
                    selectedUnit = p.unit;
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, decoration: InputDecoration(labelText: 'الكمية ($selectedUnit)'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: noteCtrl, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'سبب الإرجاع'), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: selectedProductId == null ? null : () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                final qty = double.tryParse(qtyCtrl.text) ?? 1;
                final db = AppDatabase.instance;
                await db.returnsDao.saveCustomerReturn(
                  header: CustomerReturnsCompanion(
                    returnNumber: drift.Value('RET-${DateTime.now().millisecondsSinceEpoch}'),
                    reason: drift.Value(noteCtrl.text.trim()),
                  ),
                  items: [{'productId': selectedProductId, 'qty': qty, 'price': 0.0, 'discount': 0.0}],
                );
                ref.invalidate(customerReturnsProvider);
                ref.invalidate(productsNotifierProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ مرتجع العميل بنجاح'), backgroundColor: AppColors.success)
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error)
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('حفظ المرتجع'),
          ),
        ],
      )),
    );
  }

  Future<void> _showQuickReturnDialog() async {
    final products = await ref.read(productsRepositoryProvider).getAll();
    int? selectedProductId;
    double productPrice = 0;
    String selectedUnit = 'قطعة';
    final qtyCtrl = TextEditingController(text: '1');
    String? selectedReason;
    
    final currentUser = ref.read(authProvider).valueOrNull?.user;
    if (currentUser == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setStateDialog) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('استرجاع بدون فاتورة', textDirection: TextDirection.rtl),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning)
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                    SizedBox(width: 8),
                    Expanded(child: Text('هذا استرجاع بدون فاتورة، سيتم تسجيله للمراجعة', style: TextStyle(color: AppColors.warning))),
                  ],
                ),
              ),
              DropdownButtonFormField<int?>(
                initialValue: selectedProductId,
                decoration: const InputDecoration(labelText: 'المنتج *'),
                items: [const DropdownMenuItem(value: null, child: Text('اختر منتجاً')), ...products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))],
                onChanged: (v) => setStateDialog(() {
                  selectedProductId = v;
                  if (v != null) {
                    final p = products.firstWhere((pr) => pr.id == v);
                    selectedUnit = p.unit;
                    productPrice = p.sellPrice;
                  }
                }),
              ),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, decoration: InputDecoration(labelText: 'الكمية ($selectedUnit) *'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'السبب *'),
                initialValue: selectedReason,
                items: ['بدون فاتورة', 'عيب في المنتج', 'تبديل'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setStateDialog(() => selectedReason = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
            onPressed: (selectedProductId == null || selectedReason == null) ? null : () async {
              final qty = double.tryParse(qtyCtrl.text) ?? 0;
              if (qty <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('الكمية يجب أن تكون أكبر من 0')));
                return;
              }
              Navigator.pop(ctx);
              
              final refundAmount = productPrice * qty;
              int? approvedByUserId;
              
              if (refundAmount > currentUser.refundLimit && currentUser.roleId != 1) { // 1 = Admin
                final approver = await showDialog<dynamic>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const ManagerApprovalDialog(
                    requiredPermission: 'pos.refund',
                    actionDescription: 'تجاوز حد المرتجع المسموح.',
                  ),
                );
                if (approver == null) {
                  return; // Cancelled
                }
                approvedByUserId = approver.id;
              }

              setState(() => _isLoading = true);
              try {
                final db = AppDatabase.instance;
                final saleService = PosSaleService(db);
                await saleService.processQuickReturn(
                  productId: selectedProductId!,
                  quantity: qty,
                  refundAmount: refundAmount,
                  userId: currentUser.id,
                  reason: selectedReason!,
                  approvedByUserId: approvedByUserId,
                );
                
                ref.invalidate(customerReturnsProvider);
                ref.invalidate(productsNotifierProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم الاسترجاع بدون فاتورة بنجاح'), backgroundColor: AppColors.success)
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error)
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('تأكيد الاسترجاع'),
          ),
        ],
      )),
    );
  }
}
