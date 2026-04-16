// lib/features/customers/screens/customer_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/stat_card.dart';
import '../providers/customers_provider.dart';
import '../providers/customer_accounts_provider.dart';
import 'widgets/debt_aging_widget.dart';

class CustomerProfileScreen extends ConsumerStatefulWidget {
  final int customerId;

  const CustomerProfileScreen({super.key, required this.customerId});

  @override
  ConsumerState<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  final _nf = NumberFormat('#,##0.##');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<Customer?>(
        future: ref.read(customersRepositoryProvider).getById(widget.customerId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('خطأ: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
          }
          final customer = snapshot.data;
          if (customer == null) {
            return const Center(child: Text('العميل غير موجود', style: TextStyle(color: AppColors.textHint)));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: customer.isActive 
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      customer.isActive ? 'نشط' : 'معطل',
                      style: TextStyle(
                        color: customer.isActive ? AppColors.success : AppColors.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/customers/payments/${customer.id}'),
                    icon: const Icon(Icons.payments_rounded, size: 20),
                    label: const Text('تسجيل دفعة / تسوية', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // KPI Stats Row (Total Spent, Invoices, Last Purchase, CURRENT BALANCE)
              FutureBuilder<Map<String, dynamic>>(
                future: ref.read(customersRepositoryProvider).getStats(widget.customerId),
                builder: (context, statsSnapshot) {
                  final stats = statsSnapshot.data ?? {'totalSpent': 0.0, 'invoiceCount': 0, 'lastPurchaseDate': null};
                  final totalSpent = stats['totalSpent'] as double;
                  final invoiceCount = stats['invoiceCount'] as int;
                  final lastPurchaseDate = stats['lastPurchaseDate'] as DateTime?;

                  return Consumer(
                    builder: (ctx, r, _) {
                      final balAsync = r.watch(customerBalanceProvider(customer.id));
                      final bal = balAsync.valueOrNull ?? 0.0;
                      
                      return Row(
                        children: [
                          Expanded(
                            child: StatCard(
                              title: 'إجمالي المشتريات',
                              value: '${_nf.format(totalSpent)} د.ع',
                              icon: Icons.account_balance_wallet_rounded,
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
                              title: 'الرصيد (دين)',
                              value: '${_nf.format(bal.abs())} د.ع',
                              icon: Icons.account_balance_rounded,
                              color: bal > 0 ? Colors.red : (bal < 0 ? Colors.green : AppColors.textSecondary),
                            ),
                          ),
                        ],
                      );
                    }
                  );
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
                          const Text('بيانات التواصل', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 32,
                            runSpacing: 16,
                            children: [
                              _DetailItem(icon: Icons.phone_rounded, label: 'رقم الهاتف', value: customer.phone ?? '-'),
                              _DetailItem(icon: Icons.email_rounded, label: 'البريد الإلكتروني', value: customer.email ?? '-'),
                              _DetailItem(icon: Icons.location_on_rounded, label: 'العنوان', value: customer.address ?? '-'),
                              _DetailItem(icon: Icons.security_rounded, label: 'سقف الدين المسموح', value: customer.creditLimit > 0 ? '${_nf.format(customer.creditLimit)} د.ع' : 'بدون سقف'),
                            ],
                          ),
                          if (customer.notes != null && customer.notes!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 16),
                            const Text('ملاحظات', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                            const SizedBox(height: 8),
                            Text(customer.notes!, style: const TextStyle(color: AppColors.textPrimary)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 1,
                    child: DebtAgingWidget(customerId: customer.id),
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
                            _InvoicesTab(customerId: customer.id, nf: _nf),
                            _TransactionsTab(customerId: customer.id, nf: _nf),
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
  final int customerId;
  final NumberFormat nf;
  const _InvoicesTab({required this.customerId, required this.nf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<SalesInvoice>>(
      future: ref.read(customersRepositoryProvider).getInvoices(customerId),
      builder: (context, invoicesSnapshot) {
        if (invoicesSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final invoices = invoicesSnapshot.data ?? [];
        if (invoices.isEmpty) {
          return const Center(child: Text('لا توجد فواتير سابقة لهذا العميل', style: TextStyle(color: AppColors.textSecondary)));
        }
        
        return Card(
          child: ListView.separated(
            itemCount: invoices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final inv = invoices[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(Icons.receipt_rounded, color: AppColors.primary, size: 20),
                ),
                title: Text('فاتورة رقم: ${inv.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(inv.saleDate)),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${nf.format(inv.total)} د.ع', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                    if (inv.debtAmount > 0)
                      Text('آجل: ${nf.format(inv.debtAmount)} د.ع', style: const TextStyle(fontSize: 12, color: Colors.orange))
                    else
                      Text(inv.paymentMethod == 'CASH' ? 'نقدي' : inv.paymentMethod == 'CARD' ? 'بطاقة' : 'متعدد', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  final int customerId;
  final NumberFormat nf;
  const _TransactionsTab({required this.customerId, required this.nf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(customerHistoryProvider(customerId));
    
    return historyAsync.when(
      data: (history) {
        if (history.isEmpty) {
          return const Center(child: Text('لا توجد حركات سابقة لهذا العميل', style: TextStyle(color: AppColors.textSecondary)));
        }
        return Card(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: history.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final tx = history[index];
              final isSale = tx.type == 'SALE';
              final isPayment = tx.type == 'PAYMENT';
              Color cColor = isSale ? Colors.red : (isPayment ? Colors.green : Colors.orange);
              IconData cIcon = isSale ? Icons.shopping_bag_outlined : (isPayment ? Icons.payments_outlined : Icons.tune_rounded);
              String cLabel = isSale ? 'مشتريات آجلة' : (isPayment ? 'دفعة نقدية' : 'تسوية');

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: cColor.withValues(alpha: 0.1),
                  child: Icon(cIcon, color: cColor, size: 20),
                ),
                title: Text(cLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(tx.note.isEmpty ? DateFormat('yyyy/MM/dd HH:mm').format(tx.createdAt) : '${DateFormat('yyyy-MM-dd HH:mm').format(tx.createdAt)} • ${tx.note}'),
                trailing: Text('${nf.format(tx.amount.abs())} د.ع', 
                  style: TextStyle(color: cColor, fontWeight: FontWeight.bold, fontSize: 16)),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('خطأ: $e', style: const TextStyle(color: Colors.red))),
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: AppColors.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}

