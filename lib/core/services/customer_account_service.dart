import 'package:flutter/foundation.dart';
import '../database/app_database.dart';

/// Service for managing customer accounts and debt.
class CustomerAccountService {
  final AppDatabase db;

  CustomerAccountService(this.db);

  /// Processes a payment from a customer.
  Future<void> processPayment({
    required int customerId,
    required double amount,
    String? note,
  }) async {
    if (amount <= 0) throw ArgumentError('Payment amount must be positive.');

    try {
      await db.transaction(() async {
        final customer = await db.customersDao.getCustomerById(customerId);
        if (customer == null) throw Exception('Customer with ID $customerId does not exist.');

        // recordPayment handles the transaction entry and balance update in CustomerAccounts
        await db.customerAccountsDao.recordPayment(
          customerId: customerId,
          amount: amount,
          note: note ?? 'Customer payment',
        );

        await db.logsDao.insertLog(
          userId: null, // TODO: Integration with auth service
          actionType: 'CUSTOMER_PAYMENT',
          details: 'Payment of $amount from ${customer.name} (Ref: $customerId)',
        );
      });
    } catch (e, st) {
      debugPrint('[CustomerAccountService] Error in processPayment: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في معالجة دفعة العميل: ${e.toString()}');
    }
  }

  /// Manually adjusts a customer's debt balance.
  Future<void> adjustCustomerBalance({
    required int customerId,
    required double adjustment,
    required String reason,
  }) async {
    if (adjustment == 0) throw ArgumentError('Adjustment amount cannot be zero.');
    if (reason.isEmpty) throw ArgumentError('Adjustment reason is required.');

    try {
      await db.transaction(() async {
        final customer = await db.customersDao.getCustomerById(customerId);
        if (customer == null) throw Exception('Customer with ID $customerId does not exist.');

        // adjustBalance handles the transaction entry and balance update
        await db.customerAccountsDao.adjustBalance(
          customerId: customerId,
          signedAmount: adjustment,
          reason: reason,
        );

        await db.logsDao.insertLog(
          userId: null, // TODO: Integration with auth service
          actionType: 'CUSTOMER_ADJUSTMENT',
          details: 'Balance adjusted by $adjustment. Reason: $reason (Ref: $customerId)',
        );
      });
    } catch (e, st) {
      debugPrint('[CustomerAccountService] Error in adjustCustomerBalance: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في تعديل رصيد العميل: ${e.toString()}');
    }
  }
}
