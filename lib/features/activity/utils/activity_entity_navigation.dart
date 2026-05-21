import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' show Variable;

import '../../../core/activity/activity_categories.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../invoices/widgets/invoice_details_dialog.dart';
import '../../products/providers/products_provider.dart';
import '../../products/screens/widgets/product_profile_dialog.dart';
import '../providers/activity_logs_provider.dart';

/// Modular navigation from activity log entities to existing app screens/dialogs.
class ActivityEntityNavigation {
  ActivityEntityNavigation._();

  static bool isNavigable(ActivityLog log) {
    final type = log.entityType?.toLowerCase();
    final id = log.entityId;
    if (type == null || id == null) return false;
    return const {'invoice', 'user', 'product', 'return'}.contains(type) ||
        (log.category == ActivityCategories.returns && type == 'invoice');
  }

  static String? linkLabel(ActivityLog log) {
    final type = log.entityType?.toLowerCase();
    final id = log.entityId;
    if (type == null || id == null) return null;
    return switch (type) {
      'invoice' => 'فاتورة #$id',
      'user' => 'المستخدم #$id',
      'product' => 'منتج #$id',
      'return' => 'مرتجع #$id',
      _ => '$type #$id',
    };
  }

  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    ActivityLog log,
  ) async {
    final type = log.entityType?.toLowerCase();
    final id = log.entityId;
    if (type == null || id == null) return;

    switch (type) {
      case 'invoice':
        await _openInvoice(context, id);
      case 'user':
        await _openUserTimeline(context, ref, id);
      case 'product':
        await _openProduct(context, ref, id);
      case 'return':
        await _openInvoice(context, id);
      default:
        if (log.category == ActivityCategories.returns) {
          await _openInvoice(context, id);
        } else {
          _showFallback(context, 'لا يوجد عارض متاح لهذا الكيان.');
        }
    }
  }

  static Future<void> _openInvoice(BuildContext context, int invoiceId) async {
    final exists = await AppDatabase.instance.customSelect(
      'SELECT id FROM sales_invoices WHERE id = ?',
      variables: [Variable.withInt(invoiceId)],
      readsFrom: {AppDatabase.instance.salesInvoices},
    ).getSingleOrNull();

    if (!context.mounted) return;
    if (exists == null) {
      _showFallback(context, 'الفاتورة #$invoiceId غير موجودة أو تم حذفها.');
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InvoiceDetailsDialog(invoiceId: invoiceId),
    );
  }

  static Future<void> _openUserTimeline(
    BuildContext context,
    WidgetRef ref,
    int userId,
  ) async {
    final user = await AppDatabase.instance.usersDao.getUserById(userId);
    if (!context.mounted) return;
    if (user == null) {
      _showFallback(context, 'المستخدم #$userId غير موجود.');
      return;
    }

    ref.read(activityLogsFilterProvider.notifier).update(
          (f) => f.copyWith(userId: userId, page: 0),
        );
    context.push('/activity/timeline');
  }

  static Future<void> _openProduct(
    BuildContext context,
    WidgetRef ref,
    int productId,
  ) async {
    final product = await ref.read(productsRepositoryProvider).getProductById(productId);
    if (!context.mounted) return;
    if (product == null) {
      _showFallback(context, 'المنتج #$productId غير موجود.');
      return;
    }
    showProductProfileDialog(context, product);
  }

  static void _showFallback(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.warning),
    );
  }
}