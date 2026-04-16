import 'package:flutter/foundation.dart';
import '../database/app_database.dart';

/// Service to handle supplier accounts and debt transactions.
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

        final currentBalance = await db.supplierAccountsDao.getBalance(supplierId);
        
        // Prevent overpayment: check if payment exceeds current debt
        if (amount > currentBalance) {
          throw Exception(
            'Overpayment not allowed. Current debt: $currentBalance, Payment: $amount',
          );
        }

        // 2. Database Operations & Financial Update
        await db.supplierAccountsDao.addTransaction(
          supplierId: supplierId,
          type: 'PAYMENT',
          amount: -amount, // Negative decreases the debt
          note: note ?? 'Payment to supplier',
        );

        // 3. Logging
        await db.logsDao.insertLog(
          userId: null, // TODO: Integration with auth service
          actionType: 'SUPPLIER_PAYMENT',
          details: 'Payment of $amount to supplier ${supplier.name} (Ref: $supplierId)',
        );
      });
    } catch (e, st) {
      debugPrint('[SupplierAccountService] Error in processPayment: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في معالجة دفعة المورد: ${e.toString()}');
    }
  }
}
