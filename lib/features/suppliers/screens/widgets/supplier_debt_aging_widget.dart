// lib/features/suppliers/screens/widgets/supplier_debt_aging_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/theme/app_colors.dart';
import '../../providers/supplier_accounts_provider.dart';

class SupplierDebtAgingWidget extends ConsumerWidget {
  final int supplierId;
  const SupplierDebtAgingWidget({super.key, required this.supplierId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingAsync = ref.watch(supplierAgingProvider(supplierId));
    final nf = NumberFormat('#,##0.##');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.access_time_filled_rounded,
                  color: AppColors.accent, size: 24),
              SizedBox(width: 8),
              Text('أعمار الديون السابقة',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              Spacer(),
              Tooltip(
                message:
                    'يتم احتساب أعمار الديون بناءً على العمليات المعلقة وتاريخ استحقاقها',
                child: Icon(Icons.info_outline_rounded,
                    color: AppColors.textVariant, size: 20),
              )
            ],
          ),
          const SizedBox(height: 24),
          agingAsync.when(
            data: (aging) {
              final total = aging.values.fold(0.0, (sum, val) => sum + val);
              if (total == 0) {
                return const Center(
                    child: Text('لا توجد ديون مستحقة',
                        style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold)));
              }

              return Column(
                children: [
                  _AgingBar(
                      label: '0 - 7 أيام',
                      value: aging['0_7'] ?? 0,
                      total: total,
                      color: Colors.blue,
                      nf: nf),
                  const SizedBox(height: 12),
                  _AgingBar(
                      label: '8 - 30 يوم',
                      value: aging['8_30'] ?? 0,
                      total: total,
                      color: Colors.orange,
                      nf: nf),
                  const SizedBox(height: 12),
                  _AgingBar(
                      label: '+30 يوم',
                      value: aging['30_plus'] ?? 0,
                      total: total,
                      color: AppColors.error,
                      nf: nf),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('خطأ: $e')),
          )
        ],
      ),
    );
  }
}

class _AgingBar extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final Color color;
  final NumberFormat nf;

  const _AgingBar(
      {required this.label,
      required this.value,
      required this.total,
      required this.color,
      required this.nf});

  @override
  Widget build(BuildContext context) {
    if (value <= 0) return const SizedBox.shrink();
    final ratio = value / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text('${nf.format(value)} د.ع',
                style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: AppColors.border,
            color: color,
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}
