import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/permissions/permission_keys.dart';
import '../../auth/providers/permission_provider.dart';
import '../../reports/core/models/report_drill_down.dart';
import '../../reports/core/services/report_drill_down_service.dart';
import '../models/cash_ledger_event.dart';
import '../models/cash_ledger_event_type.dart';
import 'other_income_details_dialog.dart';

/// Read-only drill-down dispatcher for [CashLedgerEvent] rows.
/// Shared by Cash Ledger and Financial Dashboard Recent Activity.
class CashLedgerEventDrillDown {
  CashLedgerEventDrillDown._();

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    CashLedgerEvent event,
  ) async {
    switch (event.eventType) {
      case CashLedgerEventType.saleCash:
      case CashLedgerEventType.returnRefund:
        final invId = event.invoiceId ?? event.referenceId;
        await ReportDrillDownService.open(
          context,
          ref,
          ReportDrillDownTarget(
            type: ReportDrillDownEntityType.invoice,
            id: invId,
          ),
        );
      case CashLedgerEventType.customerPayment:
        if (event.customerId != null && event.customerId! > 1) {
          await ReportDrillDownService.open(
            context,
            ref,
            ReportDrillDownTarget(
              type: ReportDrillDownEntityType.customer,
              id: event.customerId!,
            ),
          );
        }
      case CashLedgerEventType.purchaseCash:
      case CashLedgerEventType.supplierPayment:
        if (event.supplierId != null) {
          await ReportDrillDownService.open(
            context,
            ref,
            ReportDrillDownTarget(
              type: ReportDrillDownEntityType.supplier,
              id: event.supplierId!,
            ),
          );
        }
      case CashLedgerEventType.expense:
        break;
      case CashLedgerEventType.otherIncome:
        final canView = ref.read(
          permissionProvider(PermissionKeys.financialIncomeView),
        );
        if (!canView) break;
        if (!context.mounted) break;
        await showDialog<void>(
          context: context,
          builder: (_) => OtherIncomeDetailsDialog(incomeId: event.referenceId),
        );
    }
  }
}