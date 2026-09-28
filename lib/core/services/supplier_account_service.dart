import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import 'supplier_payment_exceeds_payable_exception.dart';

/// Service to handle supplier accounts and supplier debt transactions.
class SupplierAccountService {
  final AppDatabase db;

  SupplierAccountService(this.db);

  /// Processes a payment to a supplier.
  Future<void> processPayment({
    required int supplierId,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('Payment amount must be positive.');

    try {
      await db.transaction(() async {
        // 1. Validation
        final supplier = await db.suppliersDao.getSupplierById(supplierId);
        if (supplier == null) {
          throw Exception('Supplier with ID $supplierId does not exist.');
        }

        // 2. Atomic payment guard (authoritative SUM, not cached balance)
        final insertedId = await db.supplierAccountsDao
            .recordPaymentInTransactionIfWithinPayable(
          supplierId: supplierId,
          amount: amount,
          note: note ?? 'Payment to supplier',
        );
        if (insertedId == null) {
          final currentPayable = await db.supplierAccountsDao
              .calculateBalanceFromTransactions(supplierId);
          throw SupplierPaymentExceedsPayableException(
            supplierId: supplierId,
            currentPayable: currentPayable,
            requestedAmount: amount,
          );
        }

        // 3. Logging
        await db.logsDao.insertLog(
          userId: null, // TODO: Integration with auth service
          actionType: 'SUPPLIER_PAYMENT',
          details: 'Payment of $amount to supplier ${supplier.name} (Ref: $supplierId)',
        );
      });
    } catch (e, st) {
      debugPrint('[SupplierAccountService] Error in processPayment: $e\n$st');
      if (e is SupplierPaymentExceedsPayableException) rethrow;
      if (e is Exception) rethrow;
      throw Exception('فشل في معالجة دفعة المورد: ${e.toString()}');
    }
  }
}
