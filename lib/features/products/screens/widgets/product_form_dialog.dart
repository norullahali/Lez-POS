// lib/features/products/screens/widgets/product_form_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../categories/providers/categories_provider.dart';
import '../../../suppliers/providers/suppliers_provider.dart';
import '../../models/product_model.dart';
import '../../../../core/utils/number_parser.dart';

class ProductFormDialog extends ConsumerStatefulWidget {
  final ProductModel? existing;
  const ProductFormDialog({super.key, this.existing});

  @override
  ConsumerState<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends ConsumerState<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _sellCtrl;
  late final TextEditingController _wholesaleCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _minStockCtrl;
  int? _categoryId;
  int? _supplierId;
  bool _trackExpiry = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _barcodeCtrl = TextEditingController(text: e?.barcode ?? '');
    _costCtrl = TextEditingController(text: e?.costPrice.toString() ?? '0');
    _sellCtrl = TextEditingController(text: e?.sellPrice.toString() ?? '0');
    _wholesaleCtrl = TextEditingController(text: e?.wholesalePrice.toString() ?? '0');
    _unitCtrl = TextEditingController(text: e?.unit ?? 'قطعة');
    _minStockCtrl = TextEditingController(text: e?.minStock.toString() ?? '0');
    _categoryId = e?.categoryId;
    _supplierId = e?.supplierId;
    _trackExpiry = e?.trackExpiry ?? false;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _barcodeCtrl, _costCtrl, _sellCtrl, _wholesaleCtrl, _unitCtrl, _minStockCtrl]) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? [];
    final suppliers = ref.watch(suppliersStreamProvider).valueOrNull ?? [];
    final isEdit = widget.existing != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isEdit ? 'تعديل المنتج' : 'إضافة منتج جديد', textDirection: TextDirection.rtl),
      content: SizedBox(
        width: 560,
        height: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: TextFormField(controller: _nameCtrl, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'اسم المنتج *'), validator: (v) => (v?.trim().isEmpty ?? true) ? 'الاسم مطلوب' : null)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _barcodeCtrl, decoration: const InputDecoration(labelText: 'الباركود'), keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(labelText: 'الفئة'),
                      items: [const DropdownMenuItem(value: null, child: Text('بدون فئة')), ...categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      initialValue: _supplierId,
                      decoration: const InputDecoration(labelText: 'المورد (اختياري)'),
                      items: [const DropdownMenuItem(value: null, child: Text('بدون مورد')), ...suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))],
                      onChanged: (v) => setState(() => _supplierId = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextFormField(controller: _costCtrl, decoration: const InputDecoration(labelText: 'سعر التكلفة *'), keyboardType: TextInputType.number, validator: (v) => (v ?? '').tryParseArabicDouble() == null ? 'رقم غير صالح' : null)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _sellCtrl, decoration: const InputDecoration(labelText: 'سعر البيع *'), keyboardType: TextInputType.number, validator: (v) => (v ?? '').tryParseArabicDouble() == null ? 'رقم غير صالح' : null)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _wholesaleCtrl, decoration: const InputDecoration(labelText: 'سعر الجملة'), keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextFormField(controller: _unitCtrl, textDirection: TextDirection.rtl, decoration: const InputDecoration(labelText: 'وحدة القياس'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _minStockCtrl, decoration: const InputDecoration(labelText: 'حد التنبيه (أدنى مخزون)'), keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('تتبع تاريخ الانتهاء'),
                  const SizedBox(width: 12),
                  Switch.adaptive(value: _trackExpiry, activeTrackColor: AppColors.primary, onChanged: (v) => setState(() => _trackExpiry = v)),
                ]),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(onPressed: _submit, child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة المنتج')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, ProductModel(
      id: widget.existing?.id,
      name: _nameCtrl.text.trim(),
      barcode: _barcodeCtrl.text.trim(),
      categoryId: _categoryId,
      supplierId: _supplierId,
      costPrice: _costCtrl.text.tryParseArabicDouble() ?? 0,
      sellPrice: _sellCtrl.text.tryParseArabicDouble() ?? 0,
      wholesalePrice: _wholesaleCtrl.text.tryParseArabicDouble() ?? 0,
      unit: _unitCtrl.text.trim(),
      minStock: _minStockCtrl.text.tryParseArabicDouble() ?? 0,
      trackExpiry: _trackExpiry,
      isActive: widget.existing?.isActive ?? true,
    ));
  }
}
