// lib/features/customers/screens/customer_payments_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';

import '../providers/customers_provider.dart';
import '../providers/customer_accounts_provider.dart';

class CustomerPaymentsScreen extends ConsumerStatefulWidget {
  final int? initialCustomerId;
  const CustomerPaymentsScreen({super.key, this.initialCustomerId});

  @override
  ConsumerState<CustomerPaymentsScreen> createState() =>
      _CustomerPaymentsScreenState();
}

class _CustomerPaymentsScreenState
    extends ConsumerState<CustomerPaymentsScreen> {
  int? _selectedCustomerId;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _nf = NumberFormat('#,##0.##');

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = widget.initialCustomerId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  static String _normalizeNumber(String input) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    const arabic = '۰۱۲۳۴۵۶۷۸۹';
    var result = input;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(eastern[i], '$i').replaceAll(arabic[i], '$i');
    }
    return result;
  }

  double get _amount =>
      double.tryParse(_normalizeNumber(_amountCtrl.text.trim())) ?? 0;

  Future<void> _savePayment() async {
    if (_selectedCustomerId == null) return;
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('الرجاء إدخال مبلغ صحيح أكبر من صفر'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    try {
      await ref.read(customerAccountsDaoProvider).recordPayment(
            customerId: _selectedCustomerId!,
            amount: _amount,
            note: _noteCtrl.text.trim().isEmpty
                ? 'دفعة نقدية'
                : _noteCtrl.text.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم تسجيل دفعة بقيمة ${_nf.format(_amount)} د.ع بنجاح'),
          backgroundColor: AppColors.success,
        ));
        _amountCtrl.clear();
        _noteCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('تسجيل دفعة عميل'),
        backgroundColor: AppColors.surface,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left panel: Payment form
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('بيانات الدفعة',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),

                  // Customer Selector
                  const Text('العميل',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  customersAsync.when(
                    data: (customers) {
                      // Exclude walk-in customer (id=1)
                      final list = customers
                          .where((c) => c.id != 1 && c.isActive)
                          .toList();
                      return DropdownButtonFormField<int>(
                        initialValue: _selectedCustomerId,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                        dropdownColor: AppColors.surface,
                        hint: const Text('اختر العميل المديون',
                            style: TextStyle(color: Colors.white54)),
                        items: list.map((c) {
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name,
                                style: const TextStyle(color: Colors.white)),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() {
                          _selectedCustomerId = val;
                          _amountCtrl.clear(); // reset amount on switch
                        }),
                      );
                    },
                    loading: () => const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent)),
                    error: (e, _) => Text('خطأ: $e',
                        style: const TextStyle(color: Colors.red)),
                  ),

                  const SizedBox(height: 24),

                  // Current Balance Display
                  if (_selectedCustomerId != null)
                    Consumer(
                      builder: (context, ref, _) {
                        final balAsync = ref.watch(
                            customerBalanceProvider(_selectedCustomerId!));
                        return balAsync.when(
                          data: (bal) {
                            final isCredit = bal < 0; // Store credit
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: bal > 0
                                    ? Colors.red.withValues(alpha: 0.1)
                                    : (bal < 0
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : AppColors.surface),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: bal > 0
                                      ? Colors.red.withValues(alpha: 0.3)
                                      : (bal < 0
                                          ? Colors.green.withValues(alpha: 0.3)
                                          : Colors.white12),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    isCredit ? 'رصيد دائن للمتجر' : 'الرصيد الحالي (ذمم مدينة)',
                                    style: TextStyle(
                                      color: bal > 0
                                          ? Colors.red[300]
                                          : (bal < 0 ? Colors.green[300] : Colors.white54),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_nf.format(bal.abs())} د.ع',
                                    style: TextStyle(
                                      color: bal > 0
                                          ? Colors.red
                                          : (bal < 0 ? Colors.green : Colors.white),
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          loading: () => const SizedBox(
                              height: 100,
                              child: Center(
                                  child: CircularProgressIndicator())),
                          error: (_, __) => const SizedBox(),
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // Amount
                  const Text('مبلغ الدفعة',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixText: 'د.ع',
                      suffixStyle: const TextStyle(color: Colors.white54),
                    ),
                    onChanged: (val) => setState(() {}), // refresh button state
                  ),

                  const SizedBox(height: 24),

                  // Note
                  const Text('ملاحظات (اختياري)',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 2,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      hintText: 'مثال: دفعة نقدية / حوالة بنكية...',
                      hintStyle: const TextStyle(color: Colors.white24),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _amount > 0 ? AppColors.success : Colors.grey,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('حفظ الدفعة',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      onPressed: _amount > 0 ? _savePayment : null,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right panel: Transaction History
          Expanded(
            flex: 1,
            child: Container(
              color: AppColors.surface.withValues(alpha: 0.3),
              child: _selectedCustomerId == null
                  ? Center(
                      child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_rounded,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.1)),
                        const SizedBox(height: 16),
                        Text('اختر عميلاً لعرض سجل حركاته المالي',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4))),
                      ],
                    ))
                  : _TransactionHistoryList(customerId: _selectedCustomerId!),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _TransactionHistoryList extends ConsumerWidget {
  final int customerId;
  const _TransactionHistoryList({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(customerHistoryProvider(customerId));
    final nf = NumberFormat('#,##0.##');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('سجل الحركات المالية',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ),
        Expanded(
          child: historyAsync.when(
            data: (history) {
              if (history.isEmpty) {
                return Center(
                    child: Text('لا توجد حركات سابقة لهذا العميل',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5))));
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: history.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                itemBuilder: (context, index) {
                  final tx = history[index];
                  final isSale = tx.type == 'SALE';
                  final isPayment = tx.type == 'PAYMENT';
                  final isAdj = tx.type == 'ADJUSTMENT';

                  Color typeColor = Colors.grey;
                  IconData typeIcon = Icons.info_outline;
                  String typeLabel = 'تسوية';

                  if (isSale) {
                    typeColor = Colors.red[400]!;
                    typeIcon = Icons.shopping_bag_outlined;
                    typeLabel = 'مشتريات آجلة';
                  } else if (isPayment) {
                    typeColor = Colors.green[400]!;
                    typeIcon = Icons.payments_outlined;
                    typeLabel = 'دفعة نقدية';
                  } else if (isAdj) {
                    typeColor = Colors.orange[400]!;
                    typeIcon = Icons.tune_rounded;
                    typeLabel = 'تسوية رصيد';
                  }

                  // the absolute amount makes more sense since SALE is + and PAYMENT is -
                  final displayAmt = tx.amount.abs();
                  final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt);

                  return Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(typeIcon, color: typeColor, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(typeLabel,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(tx.note.isEmpty ? '-' : tx.note,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${nf.format(displayAmt)} د.ع',
                              style: TextStyle(
                                  color: typeColor,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(dateStr,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
            error: (e, _) => Center(
                child: Text('خطأ: $e', style: const TextStyle(color: Colors.red))),
          ),
        ),
      ],
    );
  }
}
