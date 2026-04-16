// lib/features/suppliers/screens/supplier_payments_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/suppliers_provider.dart';
import '../providers/supplier_accounts_provider.dart';

class SupplierPaymentsScreen extends ConsumerStatefulWidget {
  final int supplierId;
  const SupplierPaymentsScreen({super.key, required this.supplierId});

  @override
  ConsumerState<SupplierPaymentsScreen> createState() => _SupplierPaymentsScreenState();
}

class _SupplierPaymentsScreenState extends ConsumerState<SupplierPaymentsScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPayment(double currentBalance) async {
    final amt = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رجاءً أدخل مبلغ صحيح أكبر من الصفر'), backgroundColor: AppColors.error));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final dao = ref.read(supplierAccountsDaoProvider);
      
      // We are PAYING the supplier -> reduces our debt (balance goes down).
      // Amount in PAYMENT type should be negative (as logic says: positive = increase debt, negative = decrease debt)
      // Actually, wait, the DAO takes care of it, but how do we record it?
      // "positive = increases debt, negative = decreases debt"
      // So payment MUST be -amt in addTransaction.
      await dao.addTransaction(
        supplierId: widget.supplierId,
        type: 'PAYMENT',
        amount: -amt, // Negative to REDUCE debt
        note: _noteCtrl.text.trim().isEmpty ? 'تسديد دفعة/حساب للمورد' : _noteCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الدفعة بنجاح'), backgroundColor: AppColors.success));
        ref.invalidate(supplierBalanceProvider(widget.supplierId));
        ref.invalidate(supplierHistoryProvider(widget.supplierId));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supplierAsync = ref.watch(suppliersNotifierProvider);
    final supplier = supplierAsync.valueOrNull?.firstWhere((s) => s.id == widget.supplierId);
    
    final balanceAsync = ref.watch(supplierBalanceProvider(widget.supplierId));

    if (supplier == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تسديد للمورد')),
        body: const Center(child: Text('جاري التحميل...')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('تسديد للمورد: ${supplier.name}'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBalanceCard(balanceAsync),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('تفاصيل الدفعة المالية (د.ع)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'المبلغ المدفوع *',
                            prefixIcon: Icon(Icons.attach_money_rounded),
                          ),
                          autofocus: true,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظة / رقم الإيصال',
                            prefixIcon: Icon(Icons.note_alt_outlined),
                          ),
                        ),
                        const SizedBox(height: 32),
                        balanceAsync.maybeWhen(
                          data: (bal) => ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                            ),
                            icon: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check_circle_rounded),
                            label: const Text('حفظ و تسديد المبلغ', style: TextStyle(fontSize: 16)),
                            onPressed: _isLoading ? null : () => _submitPayment(bal),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard(AsyncValue<double> balanceAsync) {
    return Card(
      color: AppColors.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('الرصيد الدائن الحالي', style: TextStyle(color: AppColors.textVariant, fontSize: 16)),
            const SizedBox(height: 8),
            balanceAsync.when(
              data: (bal) {
                final isDebt = bal > 0;
                return Text(
                  '${isDebt ? "نطلبه: " : "يطلبنا: "}${bal.abs().toStringAsFixed(0)} د.ع',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isDebt ? AppColors.error : AppColors.success,
                  ),
                  textDirection: TextDirection.ltr,
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('خطأ: $e', style: const TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }
}
