// lib/features/purchases/screens/purchase_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_overlay.dart';
import '../../products/providers/products_provider.dart';
import '../../suppliers/providers/suppliers_provider.dart';
import '../../suppliers/providers/supplier_accounts_provider.dart';
import '../models/purchase_invoice_model.dart';
import '../providers/purchases_provider.dart';

class PurchaseFormScreen extends ConsumerStatefulWidget {
  final int? editId;
  const PurchaseFormScreen({super.key, this.editId});

  @override
  ConsumerState<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends ConsumerState<PurchaseFormScreen> {
  final _invoiceNumberCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _paidAmountCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _barcodeFocus = FocusNode();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _barcodeCtrl.addListener(() {});
  }

  @override
  void dispose() {
    _invoiceNumberCtrl.dispose();
    _discountCtrl.dispose();
    _paidAmountCtrl.dispose();
    _notesCtrl.dispose();
    _searchCtrl.dispose();
    _barcodeCtrl.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(purchaseFormProvider);
    final suppliers = ref.watch(suppliersStreamProvider).valueOrNull ?? [];
    final supplierBalanceAsync = formState.supplierId != null ? ref.watch(supplierBalanceProvider(formState.supplierId!)) : const AsyncValue.data(0.0);
    final nf = NumberFormat('#,##0.##');

    return LoadingOverlay(
      isLoading: _isLoading,
      message: 'جاري حفظ الفاتورة وتحديث المخزون...',
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'تفاصيل فاتورة الشراء',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success),
                  icon: const Icon(Icons.save_rounded,
                      size: 18, color: Colors.white),
                  label: const Text('حفظ الفاتورة',
                      style: TextStyle(color: Colors.white)),
                  onPressed: formState.items.isEmpty ? null : _saveInvoice,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Header + Product search
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        // Invoice Header Card
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('معلومات الفاتورة',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                const SizedBox(height: 16),
                                Row(children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int?>(
                                      initialValue: formState.supplierId,
                                      decoration: const InputDecoration(
                                          labelText: 'المورد'),
                                      items: [
                                        const DropdownMenuItem(
                                            value: null,
                                            child: Text('بدون مورد')),
                                        ...suppliers.map((s) =>
                                            DropdownMenuItem(
                                                value: s.id,
                                                child: Text(s.name)))
                                      ],
                                      onChanged: (v) => ref
                                          .read(purchaseFormProvider.notifier)
                                          .setSupplier(
                                              v,
                                              suppliers
                                                  .firstWhere((s) => s.id == v,
                                                      orElse: () =>
                                                          suppliers.first)
                                                  .name),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: TextFormField(
                                          controller: _invoiceNumberCtrl,
                                          textDirection: TextDirection.rtl,
                                          decoration: const InputDecoration(
                                              labelText: 'رقم الفاتورة'),
                                          onChanged: (v) => ref
                                              .read(
                                                  purchaseFormProvider.notifier)
                                              .setInvoiceNumber(v))),
                                ]),
                                 const SizedBox(height: 12),
                                 Row(children: [
                                   Expanded(
                                     child: GestureDetector(
                                       onTap: () async {
                                         final picked = await showDatePicker(
                                           context: context,
                                           initialDate: formState.date,
                                           firstDate: DateTime(2020),
                                           lastDate: DateTime.now()
                                               .add(const Duration(days: 1)),
                                         );
                                         if (picked != null) {
                                           ref
                                               .read(
                                                   purchaseFormProvider.notifier)
                                               .setDate(picked);
                                         }
                                       },
                                       child: InputDecorator(
                                         decoration: const InputDecoration(
                                             labelText: 'تاريخ الشراء',
                                             suffixIcon: Icon(
                                                 Icons.calendar_today_rounded,
                                                 size: 18)),
                                         child: Text(DateFormat('yyyy/MM/dd')
                                             .format(formState.date)),
                                       ),
                                     ),
                                   ),
                                   const SizedBox(width: 12),
                                   Expanded(
                                     child: GestureDetector(
                                       onTap: () async {
                                         final picked = await showDatePicker(
                                           context: context,
                                           initialDate: formState.dueDate ?? DateTime.now(),
                                           firstDate: DateTime.now(),
                                           lastDate: DateTime.now()
                                               .add(const Duration(days: 365 * 5)),
                                         );
                                         if (picked != null) {
                                           ref
                                               .read(purchaseFormProvider.notifier)
                                               .setDueDate(picked);
                                         }
                                       },
                                       child: InputDecorator(
                                         decoration: const InputDecoration(
                                             labelText: 'تاريخ الاستحقاق',
                                             suffixIcon: Icon(
                                                 Icons.event_available_rounded,
                                                 size: 18)),
                                         child: Text(formState.dueDate != null ? DateFormat('yyyy/MM/dd').format(formState.dueDate!) : 'غير محدد'),
                                       ),
                                     ),
                                   ),
                                 ]),
                                 const SizedBox(height: 12),
                                 TextFormField(
                                     controller: _discountCtrl,
                                     decoration: const InputDecoration(
                                         labelText: 'خصم الفاتورة'),
                                     keyboardType: TextInputType.number,
                                     onChanged: (v) => ref
                                         .read(
                                             purchaseFormProvider.notifier)
                                         .setDiscount(
                                             double.tryParse(v) ?? 0)),
                                  if (supplierBalanceAsync.valueOrNull != null && supplierBalanceAsync.valueOrNull! > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                                            const SizedBox(width: 8),
                                            Text('رصيد الديون السابقة: ${nf.format(supplierBalanceAsync.valueOrNull)} د.ع', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    ),
                               ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Product search + add
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('إضافة منتج',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _barcodeCtrl,
                                  focusNode: _barcodeFocus,
                                  decoration: const InputDecoration(
                                    labelText: 'امسح الباركود أو ابحث...',
                                    prefixIcon:
                                        Icon(Icons.qr_code_scanner_rounded),
                                    suffixIcon: Icon(Icons.search_rounded),
                                  ),
                                  onSubmitted: (barcode) =>
                                      _addByBarcode(barcode.trim()),
                                ),
                                const SizedBox(height: 8),
                                Consumer(builder: (ctx, r, _) {
                                  final productsAsync =
                                      ref.watch(productsNotifierProvider);
                                  return productsAsync.when(
                                    data: (products) {
                                      if (_barcodeCtrl.text.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      final filtered = products
                                          .where((p) =>
                                              p.name.contains(
                                                  _barcodeCtrl.text) ||
                                              p.barcode
                                                  .contains(_barcodeCtrl.text))
                                          .take(5)
                                          .toList();
                                      if (filtered.isEmpty) {
                                        return const SizedBox.shrink();
                                      }
                                      return Card(
                                        elevation: 4,
                                        child: Column(
                                          children: filtered
                                              .map((p) => ListTile(
                                                    dense: true,
                                                    title: Text(p.name),
                                                    subtitle: Text(
                                                        '${p.sellPrice.toStringAsFixed(0)} د.ع'),
                                                    onTap: () {
                                                      _showAddItemDialog(
                                                          p.id!,
                                                          p.name,
                                                          p.unit,
                                                          p.costPrice);
                                                      _barcodeCtrl.clear();
                                                    },
                                                  ))
                                              .toList(),
                                        ),
                                      );
                                    },
                                    loading: () => const SizedBox.shrink(),
                                    error: (_, __) => const SizedBox.shrink(),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Right: Invoice items + totals
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: Column(
                        children: [
                          // Items header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(12)),
                            ),
                            child: Row(
                              children: [
                                Text(
                                    'بنود الفاتورة (${formState.items.length})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          // Items list
                          Expanded(
                            child: formState.items.isEmpty
                                ? const Center(
                                    child: Text(
                                        'لا توجد بنود بعد\nاضف منتجات باستخدام البحث',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: AppColors.textHint)))
                                : ListView.separated(
                                    itemCount: formState.items.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final item = formState.items[i];
                                      return ListTile(
                                        title: Text(item.productName,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        subtitle: Text(
                                            '${item.quantity.toStringAsFixed(1)} ${item.productUnit} × ${nf.format(item.unitCost)} د.ع'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('${nf.format(item.total)} د.ع',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.primary)),
                                            const SizedBox(width: 8),
                                            IconButton(
                                                icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    color: AppColors.error,
                                                    size: 18),
                                                onPressed: () => ref
                                                    .read(purchaseFormProvider
                                                        .notifier)
                                                    .removeItem(i)),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          // Totals footer
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(12)),
                            ),
                            child: Column(
                              children: [
                                _TotalRow(
                                    label: 'المجموع الفرعي:',
                                    value:
                                        '${nf.format(formState.subtotal)} د.ع'),
                                if (formState.invoiceDiscount > 0)
                                  _TotalRow(
                                      label: 'الخصم:',
                                      value:
                                          '${nf.format(formState.invoiceDiscount)} د.ع',
                                      valueColor: AppColors.error),
                                const Divider(),
                                _TotalRow(
                                    label: 'الإجمالي:',
                                    value: '${nf.format(formState.total)} د.ع',
                                    bold: true,
                                    valueColor: AppColors.primary),
                                const SizedBox(height: 12),
                                if (formState.items.isNotEmpty) ...[
                                  TextFormField(
                                    controller: _paidAmountCtrl,
                                    decoration: const InputDecoration(labelText: 'الواصل / المدفوع للمورد (د.ع)', filled: true),
                                    keyboardType: TextInputType.number,
                                    onChanged: (v) => ref.read(purchaseFormProvider.notifier).setPaidAmount(double.tryParse(v) ?? 0),
                                  ),
                                  const SizedBox(height: 8),
                                  _TotalRow(
                                      label: 'المتبقي (دين جديد):',
                                      value: '${nf.format(formState.total - formState.paidAmount)} د.ع',
                                      bold: true,
                                      valueColor: (formState.total - formState.paidAmount) > 0 ? AppColors.error : AppColors.success),
                                ]
                              ],
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

  Future<void> _addByBarcode(String barcode) async {
    if (barcode.isEmpty) return;
    final repo = ref.read(productsRepositoryProvider);
    final product = await repo.findByBarcode(barcode);
    if (product != null && mounted) {
      _showAddItemDialog(
          product.id!, product.name, product.unit, product.costPrice);
    }
    _barcodeCtrl.clear();
    _barcodeFocus.requestFocus();
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

  Future<void> _showAddItemDialog(int productId, String productName,
      String unit, double defaultCost) async {
    // إنشاء الـ controllers داخل دالة منفصلة وتلافيها بعد الإغلاق
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl =
        TextEditingController(text: defaultCost.toStringAsFixed(2));
    final discCtrl = TextEditingController(text: '0');

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          title: Text(productName, textDirection: TextDirection.rtl),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: qtyCtrl,
                    decoration: InputDecoration(labelText: 'الكمية ($unit)'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    autofocus: true),
                const SizedBox(height: 12),
                TextField(
                    controller: costCtrl,
                    decoration:
                        const InputDecoration(labelText: 'سعر الشراء'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true)),
                const SizedBox(height: 12),
                TextField(
                    controller: discCtrl,
                    decoration:
                        const InputDecoration(labelText: 'خصم البند'),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('إضافة')),
          ],
        ),
      );

      if (result == true && mounted) {
        final qty =
            double.tryParse(_normalizeNumber(qtyCtrl.text.trim())) ?? 1;
        final cost =
            double.tryParse(_normalizeNumber(costCtrl.text.trim())) ??
                defaultCost;
        final disc =
            double.tryParse(_normalizeNumber(discCtrl.text.trim())) ?? 0;
        ref.read(purchaseFormProvider.notifier).addItem(PurchaseItemModel(
              productId: productId,
              productName: productName,
              productUnit: unit,
              quantity: qty,
              unitCost: cost,
              discountAmount: disc,
              total: (qty * cost) - disc,
            ));
      }
    } finally {
      // تأكد دائماً من تحرير الـ controllers لمنع التسرب في الذاكرة
      qtyCtrl.dispose();
      costCtrl.dispose();
      discCtrl.dispose();
    }
  }

  Future<void> _saveInvoice() async {
    final formState = ref.read(purchaseFormProvider);
    if (formState.items.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final invoice = PurchaseInvoiceModel(
        supplierId: formState.supplierId,
        invoiceNumber: formState.invoiceNumber.isEmpty
            ? 'PUR-${DateTime.now().millisecondsSinceEpoch}'
            : formState.invoiceNumber,
        purchaseDate: formState.date,
        subtotal: formState.subtotal,
        discountAmount: formState.invoiceDiscount,
        total: formState.total,
        paidAmount: formState.paidAmount,
        debtAmount: formState.total - formState.paidAmount,
        dueDate: formState.dueDate,
        notes: formState.notes,
        items: formState.items,
      );

      await ref.read(purchasesNotifierProvider.notifier).save(invoice);
      ref.read(purchaseFormProvider.notifier).reset();
      ref.invalidate(productsNotifierProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم حفظ الفاتورة وتحديث المخزون بنجاح'),
            backgroundColor: AppColors.success));
        context.go('/purchases');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('خطأ: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _TotalRow(
      {required this.label,
      required this.value,
      this.bold = false,
      this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  fontSize: bold ? 16 : 14)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  fontSize: bold ? 16 : 14,
                  color: valueColor)),
        ],
      ),
    );
  }
}
