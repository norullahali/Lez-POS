// lib/features/categories/screens/widgets/category_form_dialog.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/category_model.dart';

class CategoryFormDialog extends StatefulWidget {
  final CategoryModel? existing;
  const CategoryFormDialog({super.key, this.existing});

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late int _selectedColor;

  final _colors = AppColors.categoryColors;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _selectedColor = widget.existing?.colorValue ?? _colors[0].toARGB32();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isEdit ? 'تعديل الفئة' : 'إضافة فئة جديدة',
          textDirection: TextDirection.rtl),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(labelText: 'اسم الفئة *'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  textDirection: TextDirection.rtl,
                  decoration:
                      const InputDecoration(labelText: 'الوصف (اختياري)'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text('اللون',
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: _colors.map((color) {
                    final isSelected = color.toARGB32() == _selectedColor;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedColor = color.toARGB32()),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.black54, width: 3)
                              : null,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                      color: color.withValues(alpha: 0.5),
                                      blurRadius: 8)
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
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
          child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final model = CategoryModel(
      id: widget.existing?.id,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      colorValue: _selectedColor,
    );
    Navigator.pop(context, model);
  }
}
