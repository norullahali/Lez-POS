// lib/features/customers/screens/widgets/customer_credit_refund_entry.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/theme/app_colors.dart';
import '../../providers/customer_accounts_provider.dart';
import '../../providers/customer_refund_settlement_provider.dart';
import 'customer_refund_settlement_dialog.dart';

/// Shared customer credit visibility + cash-refund entry for Step 3.1/3.2 flows.
class CustomerCreditRefundEntry extends ConsumerWidget {
  const CustomerCreditRefundEntry({
    super.key,
    required this.customerId,
    required this.customerName,
    this.returnId,
    this.returnLabel,
    this.padding = const EdgeInsets.all(0),
  });

  final int customerId;
  final String customerName;
  final int? returnId;
  final String? returnLabel;
  final EdgeInsetsGeometry padding;

  static const returnRemainingLabel =
      'المبلغ المتبقي القابل للاسترداد على هذا المرتجع';

  static const returnRemainingLoadError = 'تعذر تحميل المبلغ المتبقي للمرتجع';

  static const aggregateCreditLabelPrefix = 'الرصيد الدائن';

  static const refundButtonLabel = 'استرداد من العميل';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(customerAvailableCreditProvider(customerId));
    final moneyFmt = NumberFormat('#,##0.##');

    if (returnId == null) {
      return Padding(
        padding: padding,
        child: creditAsync.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (_, __) => const Text(
            'تعذر تحميل الرصيد الدائن',
            style: TextStyle(color: AppColors.error),
            textDirection: TextDirection.rtl,
          ),
          data: (availableCredit) => _buildContent(
            context,
            ref,
            availableCredit: availableCredit,
            moneyFmt: moneyFmt,
            returnRemaining: null,
            returnRemainingLoading: false,
            returnRemainingError: false,
          ),
        ),
      );
    }

    final returnRemainingAsync =
        ref.watch(customerReturnRemainingRefundableProvider(returnId!));

    return Padding(
      padding: padding,
      child: creditAsync.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (_, __) => const Text(
          'تعذر تحميل الرصيد الدائن',
          style: TextStyle(color: AppColors.error),
          textDirection: TextDirection.rtl,
        ),
        data: (availableCredit) {
          return returnRemainingAsync.when(
            loading: () => _buildContent(
              context,
              ref,
              availableCredit: availableCredit,
              moneyFmt: moneyFmt,
              returnRemaining: null,
              returnRemainingLoading: true,
              returnRemainingError: false,
            ),
            error: (_, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildContent(
                  context,
                  ref,
                  availableCredit: availableCredit,
                  moneyFmt: moneyFmt,
                  returnRemaining: null,
                  returnRemainingLoading: false,
                  returnRemainingError: true,
                ),
                const SizedBox(height: 8),
                const Text(
                  returnRemainingLoadError,
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
            data: (snapshot) => _buildContent(
              context,
              ref,
              availableCredit: availableCredit,
              moneyFmt: moneyFmt,
              returnRemaining: snapshot?.remainingRefundable,
              returnRemainingLoading: false,
              returnRemainingError: false,
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref, {
    required double availableCredit,
    required NumberFormat moneyFmt,
    required double? returnRemaining,
    required bool returnRemainingLoading,
    required bool returnRemainingError,
  }) {
    final hasCredit = availableCredit > customerRefundDisplayTolerance;
    final isLinked = returnId != null;
    final hasReturnRemaining = !isLinked ||
        (!returnRemainingLoading &&
            !returnRemainingError &&
            returnRemaining != null &&
            returnRemaining > customerRefundDisplayTolerance);
    final canRefund = hasCredit && hasReturnRemaining;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                color: hasCredit ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasCredit
                      ? 'الرصيد الدائن: ${moneyFmt.format(availableCredit)} د.ع'
                      : 'لا يوجد رصيد دائن متاح لهذا العميل',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color:
                        hasCredit ? AppColors.success : AppColors.textSecondary,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
        ),
        if (isLinked) ...[
          const SizedBox(height: 8),
          if (returnRemainingLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (!returnRemainingError && returnRemaining != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: returnRemaining > customerRefundDisplayTolerance
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: returnRemaining > customerRefundDisplayTolerance
                      ? AppColors.primary.withValues(alpha: 0.25)
                      : AppColors.textHint.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Icon(
                    returnRemaining > customerRefundDisplayTolerance
                        ? Icons.receipt_long_outlined
                        : Icons.info_outline_rounded,
                    size: 20,
                    color: returnRemaining > customerRefundDisplayTolerance
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$returnRemainingLabel: ${moneyFmt.format(returnRemaining)} د.ع',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: returnRemaining > customerRefundDisplayTolerance
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text(refundButtonLabel),
            onPressed: canRefund
                ? () => _openRefundDialog(
                      context,
                      ref,
                      availableCredit: availableCredit,
                      maxReturnRefundable: returnRemaining,
                    )
                : null,
          ),
        ),
        if (!canRefund)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              !hasCredit
                  ? 'لا يوجد رصيد دائن متاح للاسترداد'
                  : isLinked && !hasReturnRemaining
                      ? 'لا يوجد مبلغ متبقٍ قابل للاسترداد على هذا المرتجع'
                      : 'استرداد نقدي للعميل',
              style: const TextStyle(
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
              'استرداد نقدي للعميل',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
      ],
    );
  }

  Future<void> _openRefundDialog(
    BuildContext context,
    WidgetRef ref, {
    required double availableCredit,
    double? maxReturnRefundable,
  }) async {
    final settled = await showCustomerRefundSettlementDialog(
      context,
      ref,
      customerId: customerId,
      customerName: customerName,
      availableCredit: availableCredit,
      returnId: returnId,
      returnLabel: returnLabel,
      maxReturnRefundable: maxReturnRefundable,
    );
    if (context.mounted && settled) {
      ref.invalidate(customerAvailableCreditProvider(customerId));
      ref.invalidate(customerBalanceProvider(customerId));
      ref.invalidate(customerHistoryProvider(customerId));
      if (returnId != null) {
        ref.invalidate(customerReturnRemainingRefundableProvider(returnId!));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم استرداد المبلغ للعميل بنجاح',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }
}
