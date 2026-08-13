import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';

/// Presentation-only mapping for supplier ledger transaction rows.
class SupplierTransactionPresentation {
  const SupplierTransactionPresentation({
    required this.icon,
    required this.iconColor,
    required this.avatarBackgroundColor,
    required this.defaultLabel,
    required this.amountColor,
    required this.showPlusForPositive,
  });

  final IconData icon;
  final Color iconColor;
  final Color avatarBackgroundColor;
  final String defaultLabel;
  final Color amountColor;
  final bool showPlusForPositive;

  String titleFor(SupplierTransaction tx) =>
      tx.note.isNotEmpty ? tx.note : defaultLabel;

  String? referenceHintFor(SupplierTransaction tx) {
    final refId = tx.referenceId;
    if (refId == null) return null;
    switch (tx.type) {
      case 'RETURN':
      case 'REFUND':
        return 'مرجع: #$refId';
      default:
        return null;
    }
  }
}

SupplierTransactionPresentation resolveSupplierTransactionPresentation(
  SupplierTransaction tx,
) {
  switch (tx.type) {
    case 'PAYMENT':
      return const SupplierTransactionPresentation(
        icon: Icons.payments_rounded,
        iconColor: AppColors.success,
        avatarBackgroundColor: AppColors.successLight,
        defaultLabel: 'دفعة للمورد',
        amountColor: AppColors.success,
        showPlusForPositive: false,
      );
    case 'RETURN':
      return const SupplierTransactionPresentation(
        icon: Icons.assignment_return_rounded,
        iconColor: AppColors.warning,
        avatarBackgroundColor: AppColors.warningLight,
        defaultLabel: 'مرتجع بضاعة',
        amountColor: AppColors.warning,
        showPlusForPositive: false,
      );
    case 'REFUND':
      return const SupplierTransactionPresentation(
        icon: Icons.call_received_rounded,
        iconColor: AppColors.success,
        avatarBackgroundColor: AppColors.successLight,
        defaultLabel: 'استرداد نقدي',
        amountColor: AppColors.success,
        showPlusForPositive: true,
      );
    case 'PURCHASE':
    default:
      return const SupplierTransactionPresentation(
        icon: Icons.shopping_cart_rounded,
        iconColor: AppColors.error,
        avatarBackgroundColor: AppColors.errorLight,
        defaultLabel: 'شراء',
        amountColor: AppColors.error,
        showPlusForPositive: true,
      );
  }
}
