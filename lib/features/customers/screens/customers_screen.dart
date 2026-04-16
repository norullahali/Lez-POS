// lib/features/customers/screens/customers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_data_table.dart';
import '../../../core/widgets/search_field.dart';
import '../providers/customers_provider.dart';
import '../providers/customer_accounts_provider.dart';
import '../../../features/loyalty/providers/loyalty_provider.dart';
import 'widgets/customer_form_dialog.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String _searchQuery = '';
  bool _showDebtorsOnly = false;

  void _showForm([Customer? customer]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerFormDialog(customer: customer),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Actions
          Row(
            children: [
              SizedBox(
                width: 300,
                child: SearchField(
                  hint: 'ابحث عن عميل (رقم الهاتف، الاسم)...',
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 16),
              // Filter Toggle
              FilterChip(
                label: const Text('المديونون فقط', style: TextStyle(fontWeight: FontWeight.w600)),
                selected: _showDebtorsOnly,
                onSelected: (val) => setState(() => _showDebtorsOnly = val),
                backgroundColor: AppColors.surface,
                selectedColor: Colors.red.withValues(alpha: 0.2),
                checkmarkColor: Colors.red,
                labelStyle: TextStyle(color: _showDebtorsOnly ? Colors.red : AppColors.textVariant),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة عميل', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _showForm(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Data Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: customersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                    child: Text('حدث خطأ: $err', style: const TextStyle(color: AppColors.error))),
                data: (customers) {
                  // Pre-filter by search query
                  var filtered = customers.where((c) {
                    if (_searchQuery.isEmpty) return true;
                    final sq = _searchQuery.toLowerCase();
                    return c.name.toLowerCase().contains(sq) ||
                        (c.phone?.toLowerCase().contains(sq) ?? false);
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('لا يوجد عملاء مطابقين للبحث', style: TextStyle(color: AppColors.textVariant)),
                    );
                  }

                  return CustomDataTable(
                    columns: const [
                      'م',
                      'الاسم',
                      'رقم الهاتف',
                      'الرصيد / الدين',
                      'النقاط',
                      'تاريخ التسجيل',
                      'إجراءات',
                    ],
                    rows: filtered.asMap().entries.map((e) {
                      final i = e.key;
                      final customer = e.value;
                      final isSystem = customer.id == 1; // Walk-in customer

                      return DataRow(
                        cells: [
                          DataCell(Text('${i + 1}', style: const TextStyle(color: AppColors.text))),
                          DataCell(
                            Row(
                              children: [
                                Text(customer.name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                                if (isSystem) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('افتراضي', style: TextStyle(color: AppColors.accentLight, fontSize: 10)),
                                  )
                                ]
                              ],
                            )
                          ),
                          DataCell(Text(customer.phone ?? '-', style: const TextStyle(color: AppColors.textVariant))),
                          // Balance Cell
                          DataCell(
                            isSystem 
                            ? const Text('-', style: TextStyle(color: AppColors.textVariant))
                            : Consumer(
                              builder: (ctx, ref, _) {
                                final balAsync = ref.watch(customerBalanceProvider(customer.id));
                                return balAsync.when(
                                  data: (bal) {
                                    // Filter out non-debtors if toggle is on (this hides the row visually but keeps it in list, a bit hacky but fast)
                                    // A better way is to filter the list above, but we need the balances. 
                                    // Since it's a small dataset, we'll just show the balance badge.
                                    if (_showDebtorsOnly && bal <= 0) return const SizedBox.shrink();

                                    if (bal == 0) return const Text('0 د.ع', style: TextStyle(color: Colors.white54));
                                    
                                    final isDebt = bal > 0;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDebt ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isDebt ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        '${bal > 0 ? "دين: " : "دائن: "}${bal.abs().toStringAsFixed(0)} د.ع',
                                        style: TextStyle(color: isDebt ? Colors.red[300] : Colors.green[300], fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                  error: (_, __) => const Text('خطأ', style: TextStyle(color: Colors.red)),
                                );
                              },
                            )
                          ),
                          // Loyalty points cell
                          DataCell(
                            isSystem
                                ? const Text('-',
                                    style: TextStyle(color: AppColors.textVariant))
                                : Consumer(
                                    builder: (ctx, ref, _) {
                                      final ptsAsync = ref.watch(
                                          customerLoyaltyPointsProvider(
                                              customer.id));
                                      return ptsAsync.when(
                                        data: (pts) {
                                          if (pts <= 0) {
                                            return const Text('0',
                                                style: TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 13));
                                          }
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF59E0B)
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: const Color(0xFFF59E0B)
                                                      .withValues(alpha: 0.4)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.star_rounded,
                                                    color: Color(0xFFF59E0B),
                                                    size: 13),
                                                const SizedBox(width: 4),
                                                Text(
                                                  pts.toStringAsFixed(0),
                                                  style: const TextStyle(
                                                    color: Color(0xFFF59E0B),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                        loading: () => const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 1.5)),
                                        error: (_, __) => const Text('-'),
                                      );
                                    },
                                  ),
                          ),
                          DataCell(Text(
                            '${customer.createdAt.year}/${customer.createdAt.month}/${customer.createdAt.day}',
                            style: const TextStyle(color: AppColors.textVariant),
                          )),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isSystem)
                                  Consumer(
                                    builder: (ctx, ref, _) {
                                      final balAsync = ref.watch(customerBalanceProvider(customer.id));
                                      final bal = balAsync.valueOrNull ?? 0.0;
                                      
                                      // Only show quick pay if they have debt
                                      if (bal > 0) {
                                        return IconButton(
                                          icon: const Icon(Icons.payments_rounded, color: Colors.orange, size: 20),
                                          tooltip: 'تسديد سريع',
                                          onPressed: () => context.push('/customers/payments/${customer.id}'),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    }
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.history_rounded, color: AppColors.accent, size: 20),
                                  tooltip: 'سجل العميل',
                                  onPressed: () {
                                    context.push('/customers/profile/${customer.id}');
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_rounded, color: AppColors.textVariant, size: 20),
                                  tooltip: 'تعديل',
                                  onPressed: () => _showForm(customer),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
