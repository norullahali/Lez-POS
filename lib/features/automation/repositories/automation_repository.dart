import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../../core/database/app_database.dart';

class AutomationRepository {
  AutomationRepository(this._db);
  final AppDatabase _db;

  Future<List<Map<String, dynamic>>> fetchProductVelocity({int days = 7}) async {
    try {
      final since = DateTime.now().subtract(Duration(days: days));
      final rows = await _db.customSelect(
        '''SELECT p.id, p.name, p.current_stock, p.min_stock, p.cost_price,
                  p.supplier_id, s.name AS supplier_name,
                  COALESCE(SUM(si.quantity), 0) AS sold_qty
           FROM products p
           LEFT JOIN suppliers s ON s.id = p.supplier_id
           LEFT JOIN sale_items si ON si.product_id = p.id
           LEFT JOIN sales_invoices inv ON inv.id = si.invoice_id
             AND inv.sale_date >= ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           WHERE p.is_active = 1
           GROUP BY p.id ORDER BY sold_qty DESC LIMIT 150''',
        variables: [Variable(since)],
        readsFrom: {_db.products, _db.suppliers, _db.saleItems, _db.salesInvoices},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[AutomationRepository] fetchProductVelocity: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchCustomerDebts({double minBalance = 50}) async {
    try {
      final rows = await _db.customSelect(
        '''SELECT ca.customer_id AS id, c.name, ca.current_balance AS balance
           FROM customer_accounts ca JOIN customers c ON c.id = ca.customer_id
           WHERE ca.current_balance >= ? ORDER BY ca.current_balance DESC LIMIT 30''',
        variables: [Variable(minBalance)],
        readsFrom: {_db.customerAccounts, _db.customers},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[AutomationRepository] fetchCustomerDebts: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSupplierDebts({double minBalance = 50}) async {
    try {
      final rows = await _db.customSelect(
        '''SELECT sa.supplier_id AS id, s.name, sa.current_balance AS balance
           FROM supplier_accounts sa JOIN suppliers s ON s.id = sa.supplier_id
           WHERE sa.current_balance >= ? ORDER BY sa.current_balance DESC LIMIT 20''',
        variables: [Variable(minBalance)],
        readsFrom: {_db.supplierAccounts, _db.suppliers},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[AutomationRepository] fetchSupplierDebts: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchLoyaltyCustomers() async {
    try {
      final rows = await _db.customSelect(
        '''SELECT c.id, c.name, COALESCE(c.loyalty_points, 0) AS loyalty_points,
                  COALESCE((SELECT SUM(inv.total) FROM sales_invoices inv
                    WHERE inv.customer_id = c.id
                      AND IFNULL(inv.invoice_status, 'completed') != 'returned'), 0) AS lifetime_spend,
                  COALESCE((SELECT MAX(inv.sale_date) FROM sales_invoices inv
                    WHERE inv.customer_id = c.id), c.created_at) AS last_purchase
           FROM customers c WHERE c.is_active = 1
           ORDER BY lifetime_spend DESC LIMIT 100''',
        readsFrom: {_db.customers, _db.salesInvoices},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[AutomationRepository] fetchLoyaltyCustomers: $e\n$st');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchSalesWeekComparison() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(const Duration(days: 7));
      final prevWeekStart = weekStart.subtract(const Duration(days: 7));
      final row = await _db.customSelect(
        '''SELECT
             COALESCE(SUM(CASE WHEN sale_date >= ? AND sale_date < ? THEN total END), 0) AS this_week,
             COALESCE(SUM(CASE WHEN sale_date >= ? AND sale_date < ? THEN total END), 0) AS prev_week
           FROM sales_invoices WHERE IFNULL(invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(weekStart), Variable(todayStart), Variable(prevWeekStart), Variable(weekStart)],
        readsFrom: {_db.salesInvoices},
      ).getSingle();
      return row.data;
    } catch (e, st) {
      debugPrint('[AutomationRepository] fetchSalesWeekComparison: $e\n$st');
      return {};
    }
  }
}