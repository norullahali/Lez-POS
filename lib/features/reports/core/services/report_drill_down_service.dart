import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' show Variable;

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../activity/providers/activity_logs_provider.dart';
import '../../../auth/permissions/permission_keys.dart';
import '../../../auth/providers/permission_provider.dart';
import '../../../invoices/widgets/invoice_details_dialog.dart';
import '../../../products/providers/products_provider.dart';
import '../../../products/screens/widgets/product_profile_dialog.dart';
import '../models/report_drill_down.dart';
import '../providers/report_permissions.dart';

/// Entity-aware drill-down navigation for report rows and KPI cards.
class ReportDrillDownService {
  ReportDrillDownService._();

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    ReportDrillDownTarget target,
  ) async {
    if (!_canNavigate(ref, target.type)) {
      _snack(context, 'ليس لديك صلاحية للانتقال إلى هذا السجل');
      return;
    }

    switch (target.type) {
      case ReportDrillDownEntityType.product:
        await _openProduct(context, ref, target.id);
      case ReportDrillDownEntityType.customer:
        await _openCustomer(context, ref, target.id);
      case ReportDrillDownEntityType.supplier:
        _openSupplier(context, target.id);
      case ReportDrillDownEntityType.invoice:
        await _openInvoice(context, target.id);
      case ReportDrillDownEntityType.invoiceHistory:
        context.push('/invoices');
      case ReportDrillDownEntityType.user:
        await _openUserTimeline(context, ref, target.id);
    }
  }

  static Future<void> _openUserTimeline(
    BuildContext context,
    WidgetRef ref,
    int userId,
  ) async {
    final exists = await AppDatabase.instance.customSelect(
      'SELECT id FROM users WHERE id = ?',
      variables: [Variable.withInt(userId)],
      readsFrom: {AppDatabase.instance.usersTable},
    ).getSingleOrNull();

    if (!context.mounted) return;
    if (exists == null) {
      _snack(context, 'المستخدم #$userId غير موجود.');
      return;
    }

    ref.read(activityLogsFilterProvider.notifier).update(
          (f) => f.copyWith(userId: userId, page: 0),
        );
    context.push('/activity/timeline');
  }

  static bool _canNavigate(WidgetRef ref, ReportDrillDownEntityType type) {
    if (!ref.read(canViewReportsProvider)) return false;
    return switch (type) {
      ReportDrillDownEntityType.product =>
        ref.read(permissionProvider(PermissionKeys.productsView)),
      ReportDrillDownEntityType.supplier =>
        ref.read(permissionProvider(PermissionKeys.purchasesView)),
      ReportDrillDownEntityType.customer ||
      ReportDrillDownEntityType.invoice ||
      ReportDrillDownEntityType.invoiceHistory =>
        ref.read(canViewReportsProvider),
      ReportDrillDownEntityType.user =>
        ref.read(permissionProvider(PermissionKeys.auditView)),
    };
  }

  static Future<void> _openProduct(
    BuildContext context,
    WidgetRef ref,
    int productId,
  ) async {
    final product = await ref.read(productsRepositoryProvider).getProductById(productId);
    if (!context.mounted) return;
    if (product == null) {
      _snack(context, 'المنتج #$productId غير موجود.');
      return;
    }
    showProductProfileDialog(context, product);
  }

  static Future<void> _openCustomer(
    BuildContext context,
    WidgetRef ref,
    int customerId,
  ) async {
    final exists = await AppDatabase.instance.customSelect(
      'SELECT id FROM customers WHERE id = ?',
      variables: [Variable.withInt(customerId)],
      readsFrom: {AppDatabase.instance.customers},
    ).getSingleOrNull();

    if (!context.mounted) return;
    if (exists == null) {
      _snack(context, 'العميل #$customerId غير موجود.');
      return;
    }
    context.push('/customers/profile/$customerId');
  }

  static void _openSupplier(BuildContext context, int supplierId) {
    context.push('/suppliers/profile/$supplierId');
  }

  static Future<void> _openInvoice(BuildContext context, int invoiceId) async {
    final exists = await AppDatabase.instance.customSelect(
      'SELECT id FROM sales_invoices WHERE id = ?',
      variables: [Variable.withInt(invoiceId)],
      readsFrom: {AppDatabase.instance.salesInvoices},
    ).getSingleOrNull();

    if (!context.mounted) return;
    if (exists == null) {
      _snack(context, 'الفاتورة #$invoiceId غير موجودة أو تم حذفها.');
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InvoiceDetailsDialog(invoiceId: invoiceId),
    );
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.warning),
    );
  }
}
