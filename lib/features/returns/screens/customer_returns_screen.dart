import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_overlay.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/manual_return_idempotency_conflict_exception.dart';
import '../../../core/services/quick_return_idempotency_conflict_exception.dart';
import '../../../core/widgets/manager_approval_dialog.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pos/providers/pos_provider.dart';
import '../../products/providers/products_provider.dart';
import '../providers/manual_return_service_provider.dart';
import '../providers/return_analytics_provider.dart';
import 'widgets/smart_return_lookup_dialog.dart';
import 'widgets/customer_return_detail_dialog.dart';

const _quickReturnUuid = Uuid();
const _manualReturnUuid = Uuid();

class ManualReturnPayload {
  const ManualReturnPayload({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.reason,
    required this.userId,
  });

  final int productId;
  final double quantity;
  final double unitPrice;
  final String reason;
  final int? userId;

  bool matches(ManualReturnPayload other) {
    return productId == other.productId &&
        quantity == other.quantity &&
        unitPrice == other.unitPrice &&
        reason == other.reason &&
        userId == other.userId;
  }
}

class QuickReturnPayload {
  const QuickReturnPayload({
    required this.productId,
    required this.quantity,
    required this.refundAmount,
    required this.reason,
    required this.userId,
  });

  final int productId;
  final double quantity;
  final double refundAmount;
  final String reason;
  final int userId;

  bool matches(QuickReturnPayload other) {
    return productId == other.productId &&
        quantity == other.quantity &&
        refundAmount == other.refundAmount &&
        reason == other.reason &&
        userId == other.userId;
  }
}

final customerReturnsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
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
  ConsumerState<CustomerReturnsScreen> createState() =>
      _CustomerReturnsScreenState();
}

class _CustomerReturnsScreenState extends ConsumerState<CustomerReturnsScreen> {
  bool _isLoading = false;
  String? _quickReturnIdempotencyKey;
  QuickReturnPayload? _pendingQuickReturnPayload;
  bool _quickReturnSubmitting = false;
  String? _manualReturnIdempotencyKey;
  ManualReturnPayload? _pendingManualReturnPayload;
  bool _manualReturnSubmitting = false;

  void _clearManualReturnAttempt() {
    _manualReturnIdempotencyKey = null;
    _pendingManualReturnPayload = null;
  }

  Future<void> _submitManualReturn(ManualReturnPayload payload) async {
    if (_manualReturnSubmitting) return;

    if (_pendingManualReturnPayload != null &&
        !_pendingManualReturnPayload!.matches(payload)) {
      _clearManualReturnAttempt();
    }
    _pendingManualReturnPayload = payload;
    _manualReturnIdempotencyKey ??= _manualReturnUuid.v4();

    _manualReturnSubmitting = true;
    setState(() => _isLoading = true);
    try {
      await ref.read(manualReturnServiceProvider).processManualReturn(
            idempotencyKey: _manualReturnIdempotencyKey!,
            productId: payload.productId,
            quantity: payload.quantity,
            unitPrice: payload.unitPrice,
            reason: payload.reason,
            userId: payload.userId,
          );

      _clearManualReturnAttempt();
      ref.invalidate(customerReturnsProvider);
      ref.invalidate(productsNotifierProvider);
      invalidateReturnAnalytics(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ مرتجع العميل بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ManualReturnIdempotencyConflictException {
      _clearManualReturnAttempt();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعارض في عملية المرتجع. أعد فتح نافذة المرتجع وحاول مرة أخرى.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      _manualReturnSubmitting = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearQuickReturnAttempt() {
    _quickReturnIdempotencyKey = null;
    _pendingQuickReturnPayload = null;
  }

  Future<void> _submitQuickReturn(
    QuickReturnPayload payload, {
    int? approvedByUserId,
  }) async {
    if (_quickReturnSubmitting) return;

    if (_pendingQuickReturnPayload != null &&
        !_pendingQuickReturnPayload!.matches(payload)) {
      _clearQuickReturnAttempt();
    }
    _pendingQuickReturnPayload = payload;
    _quickReturnIdempotencyKey ??= _quickReturnUuid.v4();

    _quickReturnSubmitting = true;
    setState(() => _isLoading = true);
    try {
      await ref.read(posSaleServiceProvider).processQuickReturn(
            idempotencyKey: _quickReturnIdempotencyKey!,
            productId: payload.productId,
            quantity: payload.quantity,
            refundAmount: payload.refundAmount,
            userId: payload.userId,
            reason: payload.reason,
            approvedByUserId: approvedByUserId,
          );

      _clearQuickReturnAttempt();
      ref.invalidate(customerReturnsProvider);
      ref.invalidate(productsNotifierProvider);
      invalidateReturnAnalytics(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم الاسترجاع بدون فاتورة بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on QuickReturnIdempotencyConflictException {
      _clearQuickReturnAttempt();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعارض في عملية الاسترجاع. أعد فتح نافذة الاسترجاع وحاول مرة أخرى.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      _quickReturnSubmitting = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
              const Text('مرتجعات العملاء',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const Spacer(),
              // Smart lookup — finds and links to a real historical sale
              FilledButton.icon(
                icon: const Icon(Icons.manage_search_rounded, size: 18),
                label: const Text('البحث الذكي للإرجاع'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => showSmartReturnLookupDialog(context),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                  icon: const Icon(Icons.flash_on_rounded, size: 18),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white),
                  label: const Text('استرجاع بدون فاتورة'),
                  onPressed: _showQuickReturnDialog),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('مرتجع جديد'),
                  onPressed: _showCustomerReturnDialog),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: returnsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('خطأ: $e')),
                data: (returns) => returns.isEmpty
                    ? const Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Icon(Icons.assignment_return_outlined,
                                size: 64, color: AppColors.textHint),
                            SizedBox(height: 16),
                            Text('لا توجد مرتجعات عملاء',
                                style: TextStyle(color: AppColors.textHint)),
                          ]))
                    : Card(
                        child: ListView.separated(
                          itemCount: returns.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = returns[i];
                            final returnId = r['id'] as int;
                            return ListTile(
                              leading: const CircleAvatar(
                                  backgroundColor: AppColors.warningLight,
                                  child: Icon(Icons.assignment_return_rounded,
                                      color: AppColors.warning)),
                              title: Text(r['return_number'] as String? ?? '-',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  'فاتورة: ${r['sale_invoice_number'] ?? 'غير محدد'}'),
                              trailing: Text(r['reason'] as String? ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              onTap: () => showCustomerReturnDetailDialog(
                                context,
                                ref,
                                returnId,
                              ),
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
    _clearManualReturnAttempt();

    final invoiceCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    int? selectedProductId;
    String selectedUnit = 'قطعة';
    final qtyCtrl = TextEditingController(text: '1');
    final products = await ref.read(productsRepositoryProvider).getAll();

    final currentUser = ref.read(authProvider).valueOrNull?.user;

    if (!mounted) return;
    final payload = await showDialog<ManualReturnPayload>(
      context: context,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('مرتجع عميل جديد',
                    textDirection: TextDirection.rtl),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                          controller: invoiceCtrl,
                          textDirection: TextDirection.rtl,
                          decoration: const InputDecoration(
                              labelText: 'رقم الفاتورة الأصلية (اختياري)')),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: selectedProductId,
                        decoration:
                            const InputDecoration(labelText: 'المنتج *'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('اختر منتجاً')),
                          ...products.map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.name)))
                        ],
                        onChanged: (v) => setStateDialog(() {
                          selectedProductId = v;
                          if (v != null) {
                            final p = products.firstWhere((pr) => pr.id == v);
                            selectedUnit = p.unit;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                          controller: qtyCtrl,
                          decoration: InputDecoration(
                              labelText: 'الكمية ($selectedUnit)'),
                          keyboardType: TextInputType.number),
                      const SizedBox(height: 12),
                      TextField(
                          controller: noteCtrl,
                          textDirection: TextDirection.rtl,
                          decoration:
                              const InputDecoration(labelText: 'سبب الإرجاع'),
                          maxLines: 2),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء')),
                  ElevatedButton(
                    onPressed: (selectedProductId == null ||
                            _manualReturnSubmitting)
                        ? null
                        : () {
                            final qty = double.tryParse(qtyCtrl.text) ?? 1;
                            if (qty <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('الكمية يجب أن تكون أكبر من 0'),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(
                              ctx,
                              ManualReturnPayload(
                                productId: selectedProductId!,
                                quantity: qty,
                                unitPrice: 0.0,
                                reason: noteCtrl.text.trim(),
                                userId: currentUser?.id,
                              ),
                            );
                          },
                    child: const Text('حفظ المرتجع'),
                  ),
                ],
              )),
    );

    if (payload == null || !mounted) return;

    await _submitManualReturn(payload);
  }

  Future<void> _showQuickReturnDialog() async {
    _clearQuickReturnAttempt();

    final products = await ref.read(productsRepositoryProvider).getAll();
    int? selectedProductId;
    double productPrice = 0;
    String selectedUnit = 'قطعة';
    final qtyCtrl = TextEditingController(text: '1');
    String? selectedReason;

    final currentUser = ref.read(authProvider).valueOrNull?.user;
    if (currentUser == null) return;

    if (!mounted) return;
    final payload = await showDialog<QuickReturnPayload>(
      context: context,
      builder: (_) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('استرجاع بدون فاتورة',
                    textDirection: TextDirection.rtl),
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
                            border: Border.all(color: AppColors.warning)),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: AppColors.warning),
                            SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'هذا استرجاع بدون فاتورة، سيتم تسجيله للمراجعة',
                                    style:
                                        TextStyle(color: AppColors.warning))),
                          ],
                        ),
                      ),
                      DropdownButtonFormField<int?>(
                        initialValue: selectedProductId,
                        decoration:
                            const InputDecoration(labelText: 'المنتج *'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('اختر منتجاً')),
                          ...products.map((p) => DropdownMenuItem(
                              value: p.id, child: Text(p.name)))
                        ],
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
                      TextField(
                          controller: qtyCtrl,
                          decoration: InputDecoration(
                              labelText: 'الكمية ($selectedUnit) *'),
                          keyboardType: TextInputType.number),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(labelText: 'السبب *'),
                        initialValue: selectedReason,
                        items: ['بدون فاتورة', 'عيب في المنتج', 'تبديل']
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) =>
                            setStateDialog(() => selectedReason = v),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء')),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white),
                    onPressed: (selectedProductId == null ||
                            selectedReason == null ||
                            _quickReturnSubmitting)
                        ? null
                        : () {
                            final qty = double.tryParse(qtyCtrl.text) ?? 0;
                            if (qty <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('الكمية يجب أن تكون أكبر من 0'),
                                ),
                              );
                              return;
                            }
                            final refundAmount = productPrice * qty;
                            Navigator.pop(
                              ctx,
                              QuickReturnPayload(
                                productId: selectedProductId!,
                                quantity: qty,
                                refundAmount: refundAmount,
                                reason: selectedReason!,
                                userId: currentUser.id,
                              ),
                            );
                          },
                    child: const Text('تأكيد الاسترجاع'),
                  ),
                ],
              )),
    );

    if (payload == null || !mounted) return;

    int? approvedByUserId;
    if (payload.refundAmount > currentUser.refundLimit &&
        currentUser.roleId != 1) {
      final approver = await showDialog<dynamic>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const ManagerApprovalDialog(
          requiredPermission: 'pos.refund',
          actionDescription: 'تجاوز حد المرتجع المسموح.',
        ),
      );
      if (approver == null) {
        return;
      }
      approvedByUserId = approver.id;
    }

    await _submitQuickReturn(payload, approvedByUserId: approvedByUserId);
  }
}
