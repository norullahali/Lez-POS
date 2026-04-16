// lib/features/customers/screens/widgets/customer_form_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/customers_provider.dart';

class CustomerFormDialog extends ConsumerStatefulWidget {
  final Customer? customer;

  const CustomerFormDialog({super.key, this.customer});

  @override
  ConsumerState<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _notesCtrl;
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.customer?.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.customer?.phone ?? '');
    _emailCtrl = TextEditingController(text: widget.customer?.email ?? '');
    _addressCtrl = TextEditingController(text: widget.customer?.address ?? '');
    _notesCtrl = TextEditingController(text: widget.customer?.notes ?? '');
    _isActive = widget.customer?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final customer = Customer(
        id: widget.customer?.id ?? 0,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        address:
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        isActive: _isActive,
        createdAt: widget.customer?.createdAt ?? DateTime.now(),
        creditLimit: widget.customer?.creditLimit ?? 0.0,
        loyaltyPoints: widget.customer?.loyaltyPoints ?? 0.0,
      );

      await ref.read(customersNotifierProvider.notifier).save(customer);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ بيانات العميل بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الحفظ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.customer == null;

    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNew ? 'إضافة عميل جديد' : 'تعديل بيانات العميل',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _buildInputDecoration(
                      'اسم العميل *', Icons.person_rounded),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'لا يمكن ترك هذا الحقل فارغاً' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration:
                      _buildInputDecoration('رقم الهاتف', Icons.phone_rounded),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _buildInputDecoration(
                      'البريد الإلكتروني', Icons.email_rounded),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _buildInputDecoration(
                      'العنوان', Icons.location_on_rounded),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration:
                      _buildInputDecoration('ملاحظات', Icons.note_rounded),
                  maxLines: 3,
                ),
                if (!isNew && widget.customer?.id != 1) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('حساب نشط',
                        style: TextStyle(color: AppColors.text)),
                    subtitle: const Text('السماح بالتعامل مع هذا العميل',
                        style: TextStyle(color: AppColors.textVariant)),
                    value: _isActive,
                    activeThumbColor: AppColors.accent,
                    onChanged: (val) => setState(() => _isActive = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (widget.customer?.id == 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('الزبون العام لا يمكن تعطيله.',
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 12)),
                    ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      child: const Text('إلغاء',
                          style: TextStyle(color: AppColors.textVariant)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                      onPressed: _isLoading ? null : _save,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('حفظ البيانات'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textVariant),
      prefixIcon: Icon(icon, color: AppColors.textVariant),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
    );
  }
}
