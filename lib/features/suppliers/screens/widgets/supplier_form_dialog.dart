// lib/features/suppliers/screens/widgets/supplier_form_dialog.dart
import 'package:flutter/material.dart';
import '../../models/supplier_model.dart';

class SupplierFormDialog extends StatefulWidget {
  final SupplierModel? existing;
  const SupplierFormDialog({super.key, this.existing});

  @override
  State<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.existing?.phone ?? '');
    _addressCtrl = TextEditingController(text: widget.existing?.address ?? '');
    _notesCtrl = TextEditingController(text: widget.existing?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isEdit ? 'تعديل المورد' : 'إضافة مورد جديد',
          textDirection: TextDirection.rtl),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                    controller: _nameCtrl,
                    textDirection: TextDirection.rtl,
                    decoration:
                        const InputDecoration(labelText: 'اسم المورد *'),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'الاسم مطلوب' : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _phoneCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _addressCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                    maxLines: 2),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _notesCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(labelText: 'ملاحظات'),
                    maxLines: 2),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        ElevatedButton(
            onPressed: _submit,
            child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
        context,
        SupplierModel(
          id: widget.existing?.id,
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        ));
  }
}
