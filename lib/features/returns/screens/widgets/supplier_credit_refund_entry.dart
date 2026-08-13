// lib/features/returns/screens/widgets/supplier_credit_refund_entry.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../../suppliers/providers/supplier_accounts_provider.dart';
import '../../providers/supplier_refund_settlement_provider.dart';
import 'supplier_refund_settlement_dialog.dart';

/// Shared supplier credit visibility + cash-refund entry for Step 3.1/3.2 flows.
class SupplierCreditRefundEntry extends ConsumerWidget {
  const SupplierCreditRefundEntry({
    super.key,
    required this.supplierId,
    required this.supplierName,
    this.returnId,
    this.returnLabel,
    this.padding = const EdgeInsets.all(0),
  });

  final int supplierId;
  final String supplierName;
  final int? returnId;
  final String? returnLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(supplierAvailableCreditProvider(supplierId));
    final moneyFmt = NumberFormat('#,##0.##');

    return Padding(
      padding: padding,
      child: creditAsync.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (_, __) => const Text(
          'تعذر تحميل رصيد المورد الدائن',
          style: TextStyle(color: AppColors.error),
          textDirection: TextDirection.rtl,
        ),
        data: (availableCredit) {
          final hasCredit = availableCredit > 0.0001;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: hasCredit ? AppColors.successLight : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasCredit
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.textHint.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      hasCredit
                          ? Icons.account_balance_wallet_outlined
                          : Icons.info_outline_rounded,
                      size: 20,
                      color: hasCredit
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasCredit
                            ? 'رصيد المورد الدائن: ${moneyFmt.format(availableCredit)} د.ع'
                            : 'لا يوجد رصيد دائن متاح لهذا المورد',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: hasCredit
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('استرداد من المورد'),
                  onPressed: hasCredit
                      ? () => _openRefundDialog(
                            context,
                            ref,
                            availableCredit: availableCredit,
                          )
                      : null,
                ),
              ),
              if (!hasCredit)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'لا يوجد رصيد دائن متاح للاسترداد',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'استرداد نقدي من المورد',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openRefundDialog(
    BuildContext context,
    WidgetRef ref, {
    required double availableCredit,
  }) async {
    final settled = await showSupplierRefundSettlementDialog(
      context,
      ref,
      supplierId: supplierId,
      supplierName: supplierName,
      availableCredit: availableCredit,
      returnId: returnId,
      returnLabel: returnLabel,
    );
    if (context.mounted && settled) {
      ref.invalidate(supplierAvailableCreditProvider(supplierId));
      ref.invalidate(supplierBalanceProvider(supplierId));
      ref.invalidate(supplierHistoryProvider(supplierId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم استرداد المبلغ من المورد بنجاح',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }
}
