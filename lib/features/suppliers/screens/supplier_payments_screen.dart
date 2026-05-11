import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/suppliers_provider.dart';
import '../providers/supplier_accounts_provider.dart';

class SupplierPaymentsScreen extends ConsumerStatefulWidget {
  final int supplierId;

  const SupplierPaymentsScreen({
    super.key,
    required this.supplierId,
  });

  @override
  ConsumerState<SupplierPaymentsScreen> createState() =>
      _SupplierPaymentsScreenState();
}

class _SupplierPaymentsScreenState
    extends ConsumerState<SupplierPaymentsScreen> {
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
    final amt = double.tryParse(_amountCtrl.text);

    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل مبلغ صحيح'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dao = ref.read(supplierAccountsDaoProvider);

      await dao.addTransaction(
        supplierId: widget.supplierId,
        type: 'PAYMENT',
        amount: -amt,
        note: _noteCtrl.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم الحفظ'),
            backgroundColor: AppColors.success,
          ),
        );

        ref.invalidate(supplierBalanceProvider(widget.supplierId));

        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/suppliers');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supplierAsync = ref.watch(suppliersNotifierProvider);
    final supplier =
        supplierAsync.valueOrNull?.firstWhere((s) => s.id == widget.supplierId);

    final balanceAsync = ref.watch(supplierBalanceProvider(widget.supplierId));

    if (supplier == null) {
      return const Center(child: Text('تحميل...'));
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (context.canPop())
            ElevatedButton(
              onPressed: () => context.pop(),
              child: const Text('رجوع'),
            ),
          const SizedBox(height: 16),
          Text(
            'تسديد للمورد: ${supplier.name}',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Column(
              children: [
                _buildBalanceCard(balanceAsync),
                const SizedBox(height: 24),
                TextField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(labelText: 'المبلغ'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(labelText: 'ملاحظة'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _submitPayment(
                            balanceAsync.valueOrNull ?? 0,
                          ),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(AsyncValue<double> balanceAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: balanceAsync.when(
          data: (bal) => Text(
            'الرصيد: ${bal.toStringAsFixed(0)} د.ع',
            style: const TextStyle(fontSize: 18),
          ),
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('خطأ: $e'),
        ),
      ),
    );
  }
}
