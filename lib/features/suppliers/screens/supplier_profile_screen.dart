// lib/features/suppliers/screens/supplier_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/stat_card.dart';
import '../providers/suppliers_provider.dart';
import '../providers/supplier_accounts_provider.dart';
import '../models/supplier_model.dart';
import '../../purchases/models/purchase_invoice_model.dart';
import 'widgets/supplier_debt_aging_widget.dart';

class SupplierProfileScreen extends ConsumerStatefulWidget {
  final int supplierId;

  const SupplierProfileScreen({super.key, required this.supplierId});

  @override
  ConsumerState<SupplierProfileScreen> createState() =>
      _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends ConsumerState<SupplierProfileScreen> {
  final _nf = NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<SupplierModel?>(
        future:
            ref.read(suppliersRepositoryProvider).getById(widget.supplierId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('خطأ: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.error)));
          }
          final supplier = snapshot.data;
          if (supplier == null) {
            return const Center(
                child: Text('المورد غير موجود',
                    style: TextStyle(color: AppColors.textHint)));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    supplier.name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: supplier.isActive
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      supplier.isActive ? 'نشط' : 'معطل',
                      style: TextStyle(
                        color: supplier.isActive
                            ? AppColors.success
                            : AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () =>
                        context.go('/suppliers/payments/${supplier.id}'),
                    icon: const Icon(Icons.payments_rounded, size: 20),
                    label: const Text('تسجيل دفعة / تسديد',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // KPI Stats Row (Total Purchased, Invoices, Last Purchase, CURRENT BALANCE)
              FutureBuilder<Map<String, dynamic>>(
                future: ref
                    .read(suppliersRepositoryProvider)
                    .getStats(widget.supplierId),
                builder: (context, statsSnapshot) {
                  final stats = statsSnapshot.data ??
                      {
                        'totalPurchased': 0.0,
                        'invoiceCount': 0,
                        'lastPurchaseDate': null
                      };
                  final totalPurchased = stats['totalPurchased'] as double;
                  final invoiceCount = stats['invoiceCount'] as int;
                  final lastPurchaseDate =
                      stats['lastPurchaseDate'] as DateTime?;

                  return Consumer(builder: (ctx, r, _) {
                    final balAsync =
                        r.watch(supplierBalanceProvider(supplier.id!));
                    final bal = balAsync.valueOrNull ?? 0.0;

                    return Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'إجمالي المشتريات',
                            value: '${_nf.format(totalPurchased)} د.ع',
                            icon: Icons.inventory_2_rounded,
                            color: AppColors.info,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatCard(
                            title: 'عدد الفواتير',
                            value: invoiceCount.toString(),
                            icon: Icons.receipt_long_rounded,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatCard(
                            title: 'آخر عملية شراء',
                            value: lastPurchaseDate != null
                                ? '${lastPurchaseDate.year}/${lastPurchaseDate.month}/${lastPurchaseDate.day}'
                                : 'لا يوجد',
                            icon: Icons.timer_rounded,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: StatCard(
                            title: 'الرصيد الدائن',
                            value: '${_nf.format(bal.abs())} د.ع',
                            icon: Icons.account_balance_rounded,
                            color: bal > 0
                                ? Colors.red
                                : (bal < 0
                                    ? Colors.green
                                    : AppColors.textSecondary),
                          ),
                        ),
                      ],
                    );
                  });
                },
              ),
              const SizedBox(height: 24),

              // Details + Aging Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('بيانات التواصل',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 32,
                            runSpacing: 16,
                            children: [
                              _DetailItem(
                                  icon: Icons.phone_rounded,
                                  label: 'رقم الهاتف',
                                  value: supplier.phone.isNotEmpty
                                      ? supplier.phone
                                      : '-'),
                              _DetailItem(
                                  icon: Icons.location_on_rounded,
                                  label: 'العنوان',
                                  value: supplier.address.isNotEmpty
                                      ? supplier.address
                                      : '-'),
                            ],
                          ),
                          if (supplier.notes.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 16),
                            const Text('ملاحظات',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14)),
                            const SizedBox(height: 8),
                            Text(supplier.notes,
                                style: const TextStyle(
                                    color: AppColors.textPrimary)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 1,
                    child: SupplierDebtAgingWidget(supplierId: supplier.id!),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Tabs for Invoices vs Transactions
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const TabBar(
                        isScrollable: true,
                        indicatorColor: AppColors.accent,
                        labelColor: AppColors.accent,
                        unselectedLabelColor: AppColors.textSecondary,
                        tabs: [
                          Tab(text: 'سجل المشتريات (Invoices)'),
                          Tab(text: 'سجل الحركات المالية (Ledger)'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _InvoicesTab(supplierId: supplier.id!, nf: _nf),
                            _TransactionsTab(supplierId: supplier.id!, nf: _nf),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InvoicesTab extends ConsumerWidget {
  final int supplierId;
  final NumberFormat nf;
  const _InvoicesTab({required this.supplierId, required this.nf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<PurchaseInvoiceModel>>(
      future: ref.read(suppliersRepositoryProvider).getInvoices(supplierId),
      builder: (context, invoicesSnapshot) {
        if (invoicesSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final invoices = invoicesSnapshot.data ?? [];
        if (invoices.isEmpty) {
          return const Center(
              child: Text('لا توجد فواتير مشتريات سابقة لهذا المورد',
                  style: TextStyle(color: AppColors.textSecondary)));
        }

        return Card(
          child: ListView.separated(
            itemCount: invoices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final inv = invoices[index];
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primarySurface,
                  child: Icon(Icons.receipt_rounded, color: AppColors.primary),
                ),
                title: Text(inv.invoiceNumber,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${inv.purchaseDate.year}/${inv.purchaseDate.month}/${inv.purchaseDate.day}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${nf.format(inv.total)} د.ع',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                    if (inv.debtAmount > 0)
                      Text('الدين: ${nf.format(inv.debtAmount)}',
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 12)),
                  ],
                ),
                onTap: () {
                  // View invoice details if implemented
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  final int supplierId;
  final NumberFormat nf;
  const _TransactionsTab({required this.supplierId, required this.nf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(supplierHistoryProvider(supplierId));

    return historyAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(
              child: Text('لا توجد حركات مالية',
                  style: TextStyle(color: AppColors.textSecondary)));
        }

        return Card(
          child: ListView.separated(
            itemCount: transactions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final isPayment = tx.type == 'PAYMENT';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isPayment
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.error.withValues(alpha: 0.1),
                  child: Icon(
                    isPayment
                        ? Icons.payments_rounded
                        : Icons.shopping_cart_rounded,
                    color: isPayment ? AppColors.success : AppColors.error,
                  ),
                ),
                title: Text(
                    tx.note.isEmpty
                        ? (isPayment ? 'دفعة نقدية' : 'فاتورة مشتريات')
                        : tx.note,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle:
                    Text(DateFormat('yyyy/MM/dd HH:mm').format(tx.createdAt)),
                trailing: Text(
                  '${tx.amount > 0 ? "+" : ""}${nf.format(tx.amount)} د.ع',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: tx.amount > 0 ? AppColors.error : AppColors.success,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
          child:
              Text('خطأ: $e', style: const TextStyle(color: AppColors.error))),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppColors.textVariant),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}
