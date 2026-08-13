import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/supplier_accounts_provider.dart';
import '../../utils/supplier_transaction_display.dart';

/// Read-only supplier ledger history tab for the Supplier Profile screen.
class SupplierTransactionsTab extends ConsumerWidget {
  const SupplierTransactionsTab({
    super.key,
    required this.supplierId,
    required this.moneyFormat,
  });

  final int supplierId;
  final NumberFormat moneyFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(supplierHistoryProvider(supplierId));

    return historyAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد حركات مالية',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        return Card(
          child: ListView.separated(
            itemCount: transactions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => SupplierTransactionListTile(
              transaction: transactions[index],
              moneyFormat: moneyFormat,
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'خطأ: $e',
          style: const TextStyle(color: AppColors.error),
        ),
      ),
    );
  }
}

/// Presentation-only list tile for one supplier ledger transaction.
class SupplierTransactionListTile extends StatelessWidget {
  const SupplierTransactionListTile({
    super.key,
    required this.transaction,
    required this.moneyFormat,
  });

  final SupplierTransaction transaction;
  final NumberFormat moneyFormat;

  @override
  Widget build(BuildContext context) {
    final presentation = resolveSupplierTransactionPresentation(transaction);
    final dateText =
        DateFormat('yyyy/MM/dd HH:mm').format(transaction.createdAt);
    final referenceHint = presentation.referenceHintFor(transaction);
    final subtitle =
        referenceHint == null ? dateText : '$dateText 뿯½ $referenceHint';
    final amountPrefix =
        presentation.showPlusForPositive && transaction.amount > 0 ? '+' : '';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: presentation.avatarBackgroundColor,
        child: Icon(
          presentation.icon,
          color: presentation.iconColor,
        ),
      ),
      title: Text(
        presentation.titleFor(transaction),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: Text(
        '$amountPrefix${moneyFormat.format(transaction.amount)} د.ع',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: presentation.amountColor,
        ),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
