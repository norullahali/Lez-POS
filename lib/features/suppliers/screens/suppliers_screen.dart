// lib/features/suppliers/screens/suppliers_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/search_field.dart';
import '../models/supplier_model.dart';
import '../providers/suppliers_provider.dart';
import '../providers/supplier_accounts_provider.dart';
import 'widgets/supplier_form_dialog.dart';
import 'package:go_router/go_router.dart';

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  bool _showDebtorsOnly = false;

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersNotifierProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SearchField(
                  hint: 'ابحث عن مورد...',
                  onChanged: (q) => ref.read(suppliersNotifierProvider.notifier).search(q),
                ),
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                    Switch(
                      value: _showDebtorsOnly,
                      onChanged: (v) => setState(() => _showDebtorsOnly = v),
                      activeThumbColor: AppColors.error,
                    ),
                  const Text('المطلوبين فقط', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('إضافة مورد'),
                onPressed: () => _showForm(context, ref, null),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: suppliersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (suppliers) {
                if (suppliers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_shipping_outlined, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        Text('لا يوجد موردون', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة أول مورد'),
                          onPressed: () => _showForm(context, ref, null),
                        ),
                      ],
                    ),
                  );
                }
                return Card(
                  child: ListView.separated(
                    itemCount: suppliers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = suppliers[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primarySurface,
                          child: Text(s.name.isNotEmpty ? s.name[0] : '؟', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ),
                        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(s.phone.isNotEmpty ? s.phone : 'لا يوجد هاتف'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Consumer(
                              builder: (ctx, ref, _) {
                                final balAsync = ref.watch(supplierBalanceProvider(s.id!));
                                return balAsync.when(
                                  data: (bal) {
                                    if (_showDebtorsOnly && bal <= 0) return const SizedBox.shrink();

                                    final isDebt = bal > 0;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (bal != 0)
                                          Container(
                                            margin: const EdgeInsets.only(left: 12),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isDebt ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: isDebt ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              '${isDebt ? "يطلبنا: " : "نطلبه: "}${bal.abs().toStringAsFixed(0)} د.ع',
                                              style: TextStyle(color: isDebt ? Colors.red[300] : Colors.green[300], fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ),
                                        if (bal > 0)
                                          IconButton(
                                            icon: const Icon(Icons.payments_rounded, color: Colors.orange, size: 20),
                                            tooltip: 'تسديد سريع',
                                            onPressed: () => context.push('/suppliers/payments/${s.id}'),
                                          ),
                                      ],
                                    );
                                  },
                                  loading: () => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                  error: (_, __) => const SizedBox.shrink(),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(icon: const Icon(Icons.history_rounded, color: AppColors.accent), onPressed: () => context.push('/suppliers/profile/${s.id}'), tooltip: 'سجل المورد'),
                            IconButton(icon: const Icon(Icons.edit_rounded, color: AppColors.primary), onPressed: () => _showForm(context, ref, s), tooltip: 'تعديل'),
                            IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error), onPressed: () => _confirmDelete(context, ref, s), tooltip: 'حذف'),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref, SupplierModel? existing) async {
    final result = await showDialog<SupplierModel>(context: context, builder: (_) => SupplierFormDialog(existing: existing));
    if (result != null) {
      final notifier = ref.read(suppliersNotifierProvider.notifier);
      if (existing == null) {
        await notifier.add(result);
      } else {
        await notifier.updateSupplier(result);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, SupplierModel s) async {
    final confirmed = await ConfirmationDialog.show(context, title: 'حذف المورد', message: 'هل تريد حذف المورد "${s.name}"؟');
    if (confirmed) await ref.read(suppliersNotifierProvider.notifier).delete(s.id!);
  }
}
