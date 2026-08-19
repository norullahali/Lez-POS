// lib/features/customers/screens/widgets/customer_refund_settlement_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../providers/customer_refund_settlement_provider.dart';

Future<bool> showCustomerRefundSettlementDialog(
  BuildContext context,
  WidgetRef ref, {
  required int customerId,
  required String customerName,
  required double availableCredit,
  int? returnId,
  String? returnLabel,
}) {
  ref.read(customerRefundSettlementProvider.notifier).init(
        customerId: customerId,
        customerName: customerName,
        availableCredit: availableCredit,
        returnId: returnId,
        returnLabel: returnLabel,
      );
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const CustomerRefundSettlementDialog(),
  ).then((settled) {
    ref.read(customerRefundSettlementProvider.notifier).reset();
    return settled ?? false;
  });
}

void _closeDialog(BuildContext context, {bool settled = false}) {
  Navigator.of(context).pop(settled);
}

class CustomerRefundSettlementDialog extends ConsumerWidget {
  const CustomerRefundSettlementDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(customerRefundSettlementProvider);
    if (ui == null) {
      return const SizedBox.shrink();
    }

    final moneyFmt = NumberFormat('#,##0.##');
    final canDismiss = !ui.isSubmitting;

    return PopScope(
      canPop: canDismiss,
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'استرداد من العميل',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                        IconButton(
                          onPressed:
                              canDismiss ? () => _closeDialog(context) : null,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'العميل',
                      value: ui.customerName,
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'الرصيد الدائن المتاح',
                      value: '${moneyFmt.format(ui.availableCredit)} د.ع',
                      emphasize: true,
                    ),
                    if (ui.returnLabel != null) ...[
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'مرتجع بضاعة للعميل',
                        value: ui.returnLabel!,
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: ui.amountText,
                      enabled: !ui.isSubmitting,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.,]'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'مبلغ الاسترداد',
                        suffixText: 'د.ع',
                        errorText: ui.status ==
                                    CustomerRefundSettlementUiStatus.failure &&
                                ui.errorMessage != null &&
                                ui.amountValidationError != null
                            ? ui.errorMessage
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textDirection: TextDirection.rtl,
                      onChanged: (value) => ref
                          .read(customerRefundSettlementProvider.notifier)
                          .setAmountText(value),
                    ),
                    if (ui.remainingCreditPreview != null &&
                        ui.parsedAmount != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'الرصيد الدائن المتبقي (تقديري): ${moneyFmt.format(ui.remainingCreditPreview)} د.ع',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: ui.note,
                      enabled: !ui.isSubmitting,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'ملاحظات (اختياري)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textDirection: TextDirection.rtl,
                      onChanged: (value) => ref
                          .read(customerRefundSettlementProvider.notifier)
                          .setNote(value),
                    ),
                    if (ui.errorMessage != null &&
                        (ui.amountValidationError == null ||
                            ui.status ==
                                CustomerRefundSettlementUiStatus.failure)) ...[
                      const SizedBox(height: 12),
                      Text(
                        ui.errorMessage!,
                        style: const TextStyle(color: AppColors.error),
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed:
                                canDismiss ? () => _closeDialog(context) : null,
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: ui.canSubmit
                                ? () async {
                                    final ok = await ref
                                        .read(customerRefundSettlementProvider
                                            .notifier)
                                        .submit();
                                    if (context.mounted && ok) {
                                      _closeDialog(context, settled: true);
                                    }
                                  }
                                : null,
                            child: ui.isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('تأكيد الاسترداد'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (ui.isSubmitting)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black26,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'جاري تنفيذ الاسترداد...',
                                textDirection: TextDirection.rtl,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      textDirection: TextDirection.rtl,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: AppColors.textSecondary),
          textDirection: TextDirection.rtl,
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
              color: emphasize ? AppColors.primary : null,
            ),
            textDirection: TextDirection.rtl,
          ),
        ),
      ],
    );
  }
}
