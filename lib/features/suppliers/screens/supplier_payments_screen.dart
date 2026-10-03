import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supplier_payment_idempotency_conflict_exception.dart';
import '../../../core/services/supplier_payment_exceeds_payable_exception.dart';
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

const _supplierPaymentUuid = Uuid();

class _SupplierPaymentsScreenState
    extends ConsumerState<SupplierPaymentsScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String? _idempotencyKey;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_resetPaymentAttempt);
    _noteCtrl.addListener(_resetPaymentAttempt);
  }

  @override
  void didUpdateWidget(covariant SupplierPaymentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supplierId != widget.supplierId) {
      _resetPaymentAttempt();
    }
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_resetPaymentAttempt);
    _noteCtrl.removeListener(_resetPaymentAttempt);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _resetPaymentAttempt() {
    _idempotencyKey = null;
  }

  Future<void> _submitPayment() async {
    if (_submitting) return;

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

    _idempotencyKey ??= _supplierPaymentUuid.v4();
    setState(() => _submitting = true);

    try {
      await ref.read(supplierAccountServiceProvider).processPayment(
            idempotencyKey: _idempotencyKey!,
            supplierId: widget.supplierId,
            amount: amt,
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
        _resetPaymentAttempt();

        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/suppliers');
        }
      }
    } on SupplierPaymentIdempotencyConflictException catch (e) {
      _resetPaymentAttempt();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تنفيذ الدفعة: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      final message = e is SupplierPaymentExceedsPayableException
          ? e.localizedMessage
          : 'خطأ: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
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
                  onPressed: _submitting ? null : _submitPayment,
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
