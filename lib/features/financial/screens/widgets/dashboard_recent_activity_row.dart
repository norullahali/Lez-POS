import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../reports/modules/shared/analytics_formatters.dart';
import '../../models/cash_ledger_event.dart';
import '../../models/cash_ledger_event_type.dart';

/// Read-only recent-activity row -- matches Cash Ledger color semantics.
class DashboardRecentActivityRow extends StatelessWidget {
  const DashboardRecentActivityRow({
    super.key,
    required this.event,
    required this.onTap,
  });

  final CashLedgerEvent event;
  final VoidCallback onTap;

  static IconData _iconFor(CashLedgerEventType type) {
    return switch (type) {
      CashLedgerEventType.saleCash => Icons.point_of_sale_rounded,
      CashLedgerEventType.customerPayment => Icons.payments_rounded,
      CashLedgerEventType.customerRefund => Icons.call_made_rounded,
      CashLedgerEventType.purchaseCash => Icons.shopping_cart_checkout_rounded,
      CashLedgerEventType.supplierPayment => Icons.local_shipping_rounded,
      CashLedgerEventType.supplierRefund => Icons.call_received_rounded,
      CashLedgerEventType.returnRefund => Icons.replay_rounded,
      CashLedgerEventType.expense => Icons.receipt_long_rounded,
      CashLedgerEventType.otherIncome => Icons.savings_rounded,
    };
  }

  static Color _accentFor(CashLedgerEventType type) {
    return switch (type) {
      CashLedgerEventType.expense => AppColors.warning,
      CashLedgerEventType.otherIncome => AppColors.success,
      _ when type.isInflow => AppColors.success,
      _ => AppColors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(event.eventType);
    final amountColor = event.isInflow ? AppColors.success : AppColors.error;
    final directionLabel = event.isInflow
        ? '\u0648\u0627\u0631\u062f'
        : '\u0635\u0627\u062f\u0631';
    final directionIcon = event.isInflow
        ? Icons.arrow_circle_down_rounded
        : Icons.arrow_circle_up_rounded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(event.eventType), color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.eventType.labelAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AnalyticsFormatters.money(event.amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: amountColor,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(directionIcon, size: 14, color: amountColor),
                      const SizedBox(width: 4),
                      Text(
                        directionLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: amountColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AnalyticsFormatters.exportTimestamp.format(event.timestamp),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
