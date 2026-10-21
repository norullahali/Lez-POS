import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supplier_payment_exceeds_payable_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/suppliers_provider.dart';
import '../providers/supplier_accounts_provider.dart';
import '../supplier_payment_submit_idempotency.dart';

class SupplierPaymentsScreen extends ConsumerStatefulWidget {
  final int supplierId;

  const SupplierPaymentsScreen({
    super.key,
    required this.supplierId,
  });

  /// When true, the next post-success refresh throws once (B35 widget tests).
  @visibleForTesting
  static bool failNextPostSuccessRefreshForTesting = false;

  @override
  ConsumerState<SupplierPaymentsScreen> createState() =>
      _SupplierPaymentsScreenState();
}

const _supplierPaymentUuid = Uuid();

class _SupplierPaymentsScreenState
    extends ConsumerState<SupplierPaymentsScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final SupplierPaymentSubmitRunner _submitRunner =
      SupplierPaymentSubmitRunner();

  String? _idempotencyKey;
  int _submitGeneration = 0;
  bool _submitting = false;
  String? _pendingServiceFailureMessage;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_invalidateSubmitGeneration);
    _noteCtrl.addListener(_invalidateSubmitGeneration);
  }

  @override
  void didUpdateWidget(covariant SupplierPaymentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supplierId != widget.supplierId) {
      _invalidateSubmitGeneration();
    }
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_invalidateSubmitGeneration);
    _noteCtrl.removeListener(_invalidateSubmitGeneration);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _invalidateSubmitGeneration() {
    _submitGeneration++;
    _idempotencyKey = null;
  }

  void _resetPaymentAttempt() {
    _idempotencyKey = null;
  }

  Future<void> _submitPayment() async {
    if (_submitting || _submitRunner.inFlight) return;

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

    final capturedSupplierId = widget.supplierId;
    final generation = ++_submitGeneration;
    final noteForService = _noteCtrl.text;
    final intent = SupplierPaymentSubmitIntent(
      supplierId: capturedSupplierId,
      amount: amt,
      note: noteForService,
    );

    _idempotencyKey ??= _supplierPaymentUuid.v4();
    final paymentKey = _idempotencyKey!;

    setState(() => _submitting = true);

    try {
      final outcome = await _submitRunner.submit(
        intent: intent,
        idempotencyKey: paymentKey,
        isSubmitStillCurrent: () =>
            mounted &&
            generation == _submitGeneration &&
            widget.supplierId == capturedSupplierId,
        invokeService: (idempotencyKey) async {
          try {
            return await ref
                .read(supplierAccountServiceProvider)
                .processPayment(
                  idempotencyKey: idempotencyKey,
                  supplierId: intent.supplierId,
                  amount: intent.amount,
                  note: intent.note,
                );
          } on SupplierPaymentExceedsPayableException catch (e) {
            _pendingServiceFailureMessage = e.localizedMessage;
            rethrow;
          } catch (e) {
            _pendingServiceFailureMessage = 'خطأ: $e';
            rethrow;
          }
        },
        postSuccessRefresh: (_) async {
          if (SupplierPaymentsScreen.failNextPostSuccessRefreshForTesting) {
            SupplierPaymentsScreen.failNextPostSuccessRefreshForTesting = false;
            throw Exception('fail refresh');
          }
          ref.invalidate(supplierBalanceProvider(capturedSupplierId));
        },
      );

      if (!mounted) return;

      switch (outcome) {
        case SupplierPaymentSubmitOutcome.skippedInFlight:
          break;
        case SupplierPaymentSubmitOutcome.success:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم الحفظ'),
              backgroundColor: AppColors.success,
            ),
          );
          _resetPaymentAttempt();
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/suppliers');
          }
        case SupplierPaymentSubmitOutcome.postSuccessRefreshFailed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم حفظ الدفعة، لكن تعذر تحديث الرصيد. أعد المحاولة.',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        case SupplierPaymentSubmitOutcome.idempotencyConflict:
          _resetPaymentAttempt();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر تنفيذ الدفعة: تعارض في عملية الدفع'),
              backgroundColor: AppColors.error,
            ),
          );
        case SupplierPaymentSubmitOutcome.serviceFailure:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_pendingServiceFailureMessage ?? 'خطأ غير متوقع'),
              backgroundColor: AppColors.error,
            ),
          );
          _pendingServiceFailureMessage = null;
        case SupplierPaymentSubmitOutcome.staleCompletion:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم تجاهل نتيجة دفعة سابقة بعد تغيير البيانات.',
              ),
            ),
          );
      }
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
