// lib/features/pos/repositories/pos_repository.dart
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../models/cart_item.dart';

class PosRepository {
  final AppDatabase _db;
  PosRepository(this._db);

  Future<PosSession?> getOpenSession() => _db.salesDao.getOpenSession();

  Future<int> openSession(String cashierName, double openingCash, int? userId) =>
      _db.salesDao.openSession(
        PosSessionsCompanion(
          cashierName: Value(cashierName),
          openingCash: Value(openingCash),
          createdByUserId: Value(userId),
        ),
      );

  Future<void> closeSession(int sessionId, double closingCash) =>
      _db.salesDao.closeSession(sessionId, closingCash);

  Future<Map<String, dynamic>> getSessionSummary(int sessionId) =>
      _db.salesDao.getSessionSummary(sessionId);

  Future<List<PosSession>> getAllSessions() => _db.salesDao.getAllSessions();

  Future<int> saveSale({
    required int? sessionId,
    required String invoiceNumber,
    required List<CartItem> cartItems,
    required double invoiceDiscount,
    required PaymentInfo payment,
    required int? userId,
    required int? customerId,
  }) async {
    final subtotal = cartItems.fold(0.0, (s, i) => s + i.lineTotal);
    final total = subtotal - invoiceDiscount;
    final debtAmt = payment.debtAmount.clamp(0.0, total);

    // Everything in a single atomic DB transaction
    return _db.transaction(() async {
      final invoiceId = await _db.salesDao.saveSaleInvoice(
        header: SalesInvoicesCompanion(
          sessionId: Value(sessionId),
          invoiceNumber: Value(invoiceNumber),
          subtotal: Value(subtotal),
          discountAmount: Value(invoiceDiscount),
          total: Value(total),
          paymentMethod: Value(payment.method),
          cashPaid: Value(payment.cashPaid),
          cardPaid: Value(payment.cardPaid),
          changeAmount: Value(payment.change),
          debtAmount: Value(debtAmt),
          createdByUserId: Value(userId),
          customerId: Value(customerId),
        ),
        items: cartItems.map((item) => {
          'productId': item.product.id,
          'qty': item.quantity,
          'price': item.unitPrice,
          'cost': item.product.costPrice,
          'discount': item.discount,
        }).toList(),
      );

      // If there is a debt portion, record a customer transaction
      if (debtAmt > 0 && customerId != null && customerId != 1) {
        await _db.customerAccountsDao.recordSale(
          customerId: customerId,
          amount: debtAmt,
          invoiceId: invoiceId,
          note: 'فاتورة رقم $invoiceNumber',
        );
      }

      return invoiceId;
    });
  }

  /// Settle a previous debt directly from POS (no new sale).
  Future<void> settleDebt({
    required int customerId,
    required double amount,
    String note = 'تسوية دين من POS',
  }) async {
    await _db.customerAccountsDao.recordPayment(
      customerId: customerId,
      amount: amount,
      note: note,
    );
  }

  Future<Map<String, dynamic>> getDailyTotals(DateTime date) =>
      _db.salesDao.getDailyTotals(date);

  Future<List<Map<String, dynamic>>> getTopProducts(DateTime from, DateTime to) =>
      _db.salesDao.getTopSellingProducts(from, to);
}
