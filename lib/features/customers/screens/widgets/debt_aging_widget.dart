// lib/features/customers/screens/widgets/debt_aging_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/theme/app_colors.dart';
import '../../providers/customer_accounts_provider.dart';

class DebtAgingWidget extends ConsumerWidget {
  final int customerId;
  const DebtAgingWidget({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agingAsync = ref.watch(customerAgingProvider(customerId));
    final nf = NumberFormat('#,##0.##');

    return agingAsync.when(
      data: (buckets) {
        final b1 = buckets['0_7'] ?? 0;
        final b2 = buckets['8_30'] ?? 0;
        final b3 = buckets['30_plus'] ?? 0;
        final total = b1 + b2 + b3;
        
        if (total <= 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.posPanelLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.access_time_rounded, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Text('أعمار الديون (منذ أول عملية شراء غير مسددة)', 
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Bucket(label: '0 - 7 أيام', amount: b1, color: Colors.green[400]!, nf: nf),
                  const SizedBox(width: 12),
                  _Bucket(label: '8 - 30 يوم', amount: b2, color: Colors.orange[400]!, nf: nf),
                  const SizedBox(width: 12),
                  _Bucket(label: 'أكثر من 30 يوم', amount: b3, color: Colors.red[400]!, nf: nf),
                ],
              )
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Text('خطأ: $e', style: const TextStyle(color: Colors.red)),
    );
  }
}

class _Bucket extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final NumberFormat nf;

  const _Bucket({required this.label, required this.amount, required this.color, required this.nf});

  @override
  Widget build(BuildContext context) {
    final hasAmount = amount > 0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: hasAmount ? color.withValues(alpha: 0.1) : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasAmount ? color.withValues(alpha: 0.3) : Colors.white12),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(color: hasAmount ? color : Colors.white54, fontSize: 11)),
            const SizedBox(height: 4),
            Text('${nf.format(amount)} د.ع', 
                 style: TextStyle(color: hasAmount ? color : Colors.white54, fontWeight: FontWeight.w700, fontSize: 13),
                 textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
