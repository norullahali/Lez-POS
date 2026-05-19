// lib/core/database/daos/sales_dao.dart
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sales_invoices_table.dart';
import '../tables/sale_items_table.dart';
import '../tables/pos_sessions_table.dart';
import '../tables/stock_ledger_table.dart';
import '../../constants/movement_types.dart';
import '../../services/stock_guard.dart';

part 'sales_dao.g.dart';

@DriftAccessor(tables: [SalesInvoices, SaleItems, PosSessions, StockLedger])
class SalesDao extends DatabaseAccessor<AppDatabase> with _$SalesDaoMixin {
  SalesDao(super.db);

  // --- Sessions ---
  /// Returns the active (unclosed) session opened today.
  /// Sessions from previous days are intentionally excluded — they are stale
  /// and a new session must be opened each working day.
  Future<PosSession?> getOpenSession() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return (select(posSessions)
          ..where((s) =>
              s.isClosed.equals(false) &
              s.openedAt.isBiggerOrEqualValue(startOfToday))
          ..orderBy([(s) => OrderingTerm.desc(s.openedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> openSession(PosSessionsCompanion session) =>
      into(posSessions).insert(session);

  Future<int> closeSession({
    required int sessionId,
    required double closingCash,
    double? expectedCashAmount,
    double? cashDifference,
    int? closedByUserId,
    String? notes,
  }) =>
      (update(posSessions)..where((s) => s.id.equals(sessionId))).write(
        PosSessionsCompanion(
          isClosed: const Value(true),
          closedAt: Value(DateTime.now()),
          closingCash: Value(closingCash),
          closedByUserId: Value(closedByUserId),
          expectedCashAmount: Value(expectedCashAmount),
          cashDifference: Value(cashDifference),
          notes: Value(notes),
        ),
      );

  Future<List<PosSession>> getAllSessions() =>
      (select(posSessions)..orderBy([(s) => OrderingTerm.desc(s.openedAt)])).get();

  // --- Sales ---
  Future<List<SalesInvoice>> getAllInvoices() =>
      (select(salesInvoices)
        ..orderBy([(i) => OrderingTerm.desc(i.saleDate)]))
          .get();

  Future<List<SalesInvoice>> getInvoicesByDateRange(
      DateTime from, DateTime to) =>
      (select(salesInvoices)
        ..where((i) => i.saleDate.isBetweenValues(from, to))
        ..orderBy([(i) => OrderingTerm.desc(i.saleDate)]))
          .get();

  Future<SalesInvoice?> getInvoiceById(int id) =>
      (select(salesInvoices)..where((i) => i.id.equals(id))).getSingleOrNull();

  Future<SalesInvoice?> getInvoiceByNumber(String number) =>
      (select(salesInvoices)..where((i) => i.invoiceNumber.equals(number)))
          .getSingleOrNull();

  Future<List<SaleItem>> getItemsForInvoice(int invoiceId) =>
      (select(saleItems)..where((i) => i.invoiceId.equals(invoiceId))).get();

  /// Daily totals for dashboard
  Future<Map<String, dynamic>> getDailyTotals(DateTime date) async {
    try {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    debugPrint('[SalesDao] getDailyTotals: $start -> $end');
    final result = await customSelect(
      '''SELECT COUNT(*) as count, COALESCE(SUM(total), 0) as total,
         COALESCE(SUM(si.total - COALESCE(costs.cost,0)), 0) as profit,
         COALESCE(SUM(cash_paid), 0) as cash, COALESCE(SUM(card_paid), 0) as card
         FROM sales_invoices si
         LEFT JOIN (
           SELECT invoice_id, SUM(quantity * unit_cost) as cost FROM sale_items GROUP BY invoice_id
         ) costs ON costs.invoice_id = si.id
         WHERE si.sale_date >= ? AND si.sale_date < ?
         AND IFNULL(si.invoice_status, 'completed') != 'returned' ''',
      variables: [Variable(start), Variable(end)],
      readsFrom: {salesInvoices, saleItems},
    ).getSingleOrNull();
    return result?.data ?? {'count': 0, 'total': 0.0, 'profit': 0.0, 'cash': 0.0, 'card': 0.0};
    } catch (e, st) {
      debugPrint('[SalesDao] getDailyTotals error: $e\n$st');
      return {'count': 0, 'total': 0.0, 'profit': 0.0, 'cash': 0.0, 'card': 0.0};
    }
  }

  /// Monthly totals for reports
  Future<List<Map<String, dynamic>>> getMonthlyTotals(int year) async {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year + 1, 1, 1);
    final rows = await customSelect(
      '''SELECT 
           strftime('%m', si.sale_date) as month,
           COUNT(*) as invoice_count, 
           COALESCE(SUM(si.total), 0) as total_revenue,
           COALESCE(SUM(si.total - COALESCE(costs.cost,0)), 0) as total_profit
         FROM sales_invoices si
         LEFT JOIN (
           SELECT invoice_id, SUM(quantity * unit_cost) as cost FROM sale_items GROUP BY invoice_id
         ) costs ON costs.invoice_id = si.id
         WHERE si.sale_date >= ? AND si.sale_date < ?
         AND IFNULL(si.invoice_status, 'completed') != 'returned'
         GROUP BY strftime('%m', si.sale_date)
         ORDER BY month ASC''',
      variables: [Variable(start), Variable(end)],
      readsFrom: {salesInvoices, saleItems},
    ).get();
    return rows.map((r) => r.data).toList();
  }

  /// Top selling products
  Future<List<Map<String, dynamic>>> getTopSellingProducts(DateTime from, DateTime to, {int limit = 10}) async {
    try {
    debugPrint('[SalesDao] getTopSellingProducts: $from -> $to');
    final rows = await customSelect('''
      SELECT si.product_id, p.name, SUM(si.quantity) as total_qty, SUM(si.total) as total_revenue
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      JOIN sales_invoices inv ON inv.id = si.invoice_id
      WHERE inv.sale_date >= ? AND inv.sale_date < ?
      AND IFNULL(inv.invoice_status, 'completed') != 'returned'
      GROUP BY si.product_id
      ORDER BY total_qty DESC
      LIMIT ?
    ''', variables: [Variable(from), Variable(to), Variable.withInt(limit)], readsFrom: {saleItems, salesInvoices}).get();
    return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[SalesDao] getTopSellingProducts error: $e\n$st');
      return [];
    }
  }

  /// Daily session summary
  Future<Map<String, dynamic>> getSessionSummary(int sessionId) async {
    final result = await customSelect(
      '''SELECT
           COUNT(CASE WHEN IFNULL(invoice_status, 'completed') NOT IN ('returned') THEN 1 END) as count,
           COALESCE(SUM(CASE WHEN IFNULL(invoice_status, 'completed') NOT IN ('returned') THEN total END), 0) as total,
           COALESCE(SUM(CASE WHEN IFNULL(invoice_status, 'completed') NOT IN ('returned') THEN cash_paid END), 0) as cash,
           COALESCE(SUM(CASE WHEN IFNULL(invoice_status, 'completed') NOT IN ('returned') THEN card_paid END), 0) as card,
           COALESCE(SUM(CASE WHEN invoice_status = 'returned' THEN cash_paid END), 0) as cash_returns
         FROM sales_invoices WHERE session_id = ?''',
      variables: [Variable.withInt(sessionId)],
      readsFrom: {salesInvoices},
    ).getSingleOrNull();
    return result?.data ??
        {'count': 0, 'total': 0.0, 'cash': 0.0, 'card': 0.0, 'cash_returns': 0.0};
  }

  /// Save complete sale invoice with items and stock ledger entries
  Future<int> saveSaleInvoice({
    required SalesInvoicesCompanion header,
    required List<Map<String, dynamic>> items,
  }) async {
    return transaction(() async {
      final invoiceId = await into(salesInvoices).insert(header);
      for (final item in items) {
        final productId = item['productId'] as int;
        final qty = (item['qty'] as num).toDouble();
        final price = (item['price'] as num).toDouble();
        final cost = (item['cost'] as num?)?.toDouble() ?? 0.0;
        final discount = (item['discount'] as num?)?.toDouble() ?? 0.0;
        final total = (qty * price) - discount;

        final itemId = await into(saleItems).insert(
          SaleItemsCompanion(
            invoiceId: Value(invoiceId),
            productId: Value(productId),
            quantity: Value(qty),
            unitPrice: Value(price),
            unitCost: Value(cost),
            discountAmount: Value(discount),
            total: Value(total),
          ),
        );

        await into(stockLedger).insert(
          StockLedgerCompanion(
            productId: Value(productId),
            movementType: Value(StockMovementType.sale.code),
            referenceId: Value(itemId),
            referenceType: const Value('sale_items'),
            quantityChange: Value(-qty), // negative = out
            unitCost: Value(cost),
          ),
        );

        // Guard-protected deduction — prevents negative stock.
        // Must be inside the enclosing transaction for atomicity.
        await StockGuard.deductStock(
          db: attachedDatabase,
          productId: productId,
          quantity: qty,
        );
      }
      return invoiceId;
    });
  }
}
