import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';

/// Read-only SQL for operational intelligence heuristics.
class OperationsIntelligenceRepository {
  OperationsIntelligenceRepository(this._db);

  final AppDatabase _db;

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endExclusive(DateTime d) =>
      _startOfDay(d).add(const Duration(days: 1));

  int get _todayMs =>
      _startOfDay(DateTime.now()).millisecondsSinceEpoch;

  Future<bool> isExpiryTrackingEnabled() async {
    try {
      final batchCount = await _db.customSelect(
        'SELECT COUNT(*) AS cnt FROM product_batches',
        readsFrom: {_db.productBatches},
      ).getSingle();
      if (((batchCount.data['cnt'] as int?) ?? 0) > 0) return true;

      final tracked = await _db.customSelect(
        'SELECT COUNT(*) AS cnt FROM products WHERE track_expiry = 1',
        readsFrom: {_db.products},
      ).getSingle();
      return ((tracked.data['cnt'] as int?) ?? 0) > 0;
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] isExpiryTrackingEnabled: $e\n$st');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchDeadStockProducts({int days = 30}) async {
    try {
      final cutoff = _startOfDay(DateTime.now()).subtract(Duration(days: days));
      final rows = await _db.customSelect(
        '''SELECT p.id, p.name, p.current_stock, p.min_stock
           FROM products p
           WHERE p.is_active = 1
             AND p.current_stock > 0
             AND NOT EXISTS (
               SELECT 1 FROM sale_items si
               JOIN sales_invoices inv ON inv.id = si.invoice_id
               WHERE si.product_id = p.id
                 AND inv.sale_date >= ?
                 AND IFNULL(inv.invoice_status, 'completed') != 'returned'
             )
           ORDER BY p.current_stock DESC
           LIMIT 25''',
        variables: [Variable(cutoff)],
        readsFrom: {_db.products, _db.saleItems, _db.salesInvoices},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchDeadStockProducts: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchOverstockRiskProducts() async {
    try {
      final since = _startOfDay(DateTime.now()).subtract(const Duration(days: 14));
      final rows = await _db.customSelect(
        '''SELECT p.id, p.name, p.current_stock, p.min_stock,
                  COALESCE((
                    SELECT SUM(si.quantity) FROM sale_items si
                    JOIN sales_invoices inv ON inv.id = si.invoice_id
                    WHERE si.product_id = p.id
                      AND inv.sale_date >= ?
                      AND IFNULL(inv.invoice_status, 'completed') != 'returned'
                  ), 0) AS sold_14d
           FROM products p
           WHERE p.is_active = 1
             AND p.current_stock > MAX(p.min_stock * 3, 10)
             AND COALESCE((
               SELECT SUM(si.quantity) FROM sale_items si
               JOIN sales_invoices inv ON inv.id = si.invoice_id
               WHERE si.product_id = p.id
                 AND inv.sale_date >= ?
                 AND IFNULL(inv.invoice_status, 'completed') != 'returned'
             ), 0) < p.current_stock * 0.1
           ORDER BY p.current_stock DESC
           LIMIT 20''',
        variables: [Variable(since), Variable(since)],
        readsFrom: {_db.products, _db.saleItems, _db.salesInvoices},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchOverstockRiskProducts: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchHighMovementProducts({int days = 7}) async {
    try {
      final since = _startOfDay(DateTime.now()).subtract(Duration(days: days));
      final rows = await _db.customSelect(
        '''SELECT si.product_id AS id, p.name,
                  SUM(si.quantity) AS sold_qty,
                  p.current_stock
           FROM sale_items si
           JOIN products p ON p.id = si.product_id
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY si.product_id
           HAVING sold_qty >= MAX(p.current_stock * 2, 20)
           ORDER BY sold_qty DESC
           LIMIT 15''',
        variables: [Variable(since)],
        readsFrom: {_db.saleItems, _db.products, _db.salesInvoices},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchHighMovementProducts: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSalesVelocity({int days = 7}) async {
    try {
      final since = _startOfDay(DateTime.now()).subtract(Duration(days: days));
      final rows = await _db.customSelect(
        '''SELECT p.id, p.name, p.current_stock,
                  COALESCE(SUM(si.quantity), 0) AS sold_qty
           FROM products p
           LEFT JOIN sale_items si ON si.product_id = p.id
           LEFT JOIN sales_invoices inv ON inv.id = si.invoice_id
             AND inv.sale_date >= ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           WHERE p.is_active = 1 AND p.current_stock > 0
           GROUP BY p.id
           HAVING sold_qty > 0
           ORDER BY sold_qty DESC
           LIMIT 100''',
        variables: [Variable(since)],
        readsFrom: {_db.products, _db.saleItems, _db.salesInvoices},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchSalesVelocity: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSessionMismatches({double minDiff = 5}) async {
    try {
      final today = _startOfDay(DateTime.now());
      final rows = await _db.customSelect(
        '''SELECT s.id, s.cash_difference, s.expected_cash_amount,
                  COALESCE(u.username, u.full_name, 'كاشير') AS cashier_name,
                  s.closed_by_user_id AS user_id
           FROM pos_sessions s
           LEFT JOIN users u ON u.id = s.closed_by_user_id
           WHERE s.is_closed = 1
             AND s.closed_at >= ?
             AND ABS(COALESCE(s.cash_difference, 0)) >= ?
           ORDER BY ABS(s.cash_difference) DESC
           LIMIT 20''',
        variables: [Variable(today), Variable(minDiff)],
        readsFrom: {_db.posSessions, _db.usersTable},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchSessionMismatches: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchCashierRefundsToday({
    int minCount = 3,
    double minAmount = 100,
  }) async {
    try {
      final rows = await _db.customSelect(
        '''SELECT cashier_user_id AS user_id,
                  COALESCE(cashier_name_snapshot, 'كاشير') AS name,
                  COUNT(*) AS refund_count,
                  COALESCE(SUM(returned_amount), 0) AS refund_amount
           FROM return_audit_logs
           WHERE created_at >= ?
           GROUP BY cashier_user_id
           HAVING refund_count >= ? OR refund_amount >= ?
           ORDER BY refund_amount DESC
           LIMIT 20''',
        variables: [
          Variable.withInt(_todayMs),
          Variable.withInt(minCount),
          Variable(minAmount),
        ],
        readsFrom: {_db.returnAuditLogs},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchCashierRefundsToday: $e\n$st');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchReturnRateComparison() async {
    try {
      final todayStart = _startOfDay(DateTime.now());
      final todayEnd = _endExclusive(DateTime.now());
      final weekStart = todayStart.subtract(const Duration(days: 7));

      final todaySales = await _db.customSelect(
        '''SELECT COALESCE(SUM(total), 0) AS sales
           FROM sales_invoices
           WHERE sale_date >= ? AND sale_date < ?
             AND IFNULL(invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(todayStart), Variable(todayEnd)],
        readsFrom: {_db.salesInvoices},
      ).getSingle();

      final todayReturns = await _db.customSelect(
        '''SELECT COALESCE(SUM(returned_amount), 0) AS returns
           FROM return_audit_logs
           WHERE created_at >= ? AND created_at < ?''',
        variables: [
          Variable.withInt(todayStart.millisecondsSinceEpoch),
          Variable.withInt(todayEnd.millisecondsSinceEpoch),
        ],
        readsFrom: {_db.returnAuditLogs},
      ).getSingle();

      final weekReturns = await _db.customSelect(
        '''SELECT COALESCE(SUM(returned_amount), 0) AS returns,
                  COUNT(*) AS cnt
           FROM return_audit_logs
           WHERE created_at >= ? AND created_at < ?''',
        variables: [
          Variable.withInt(weekStart.millisecondsSinceEpoch),
          Variable.withInt(todayEnd.millisecondsSinceEpoch),
        ],
        readsFrom: {_db.returnAuditLogs},
      ).getSingle();

      final sales = (todaySales.data['sales'] as num).toDouble();
      final returns = (todayReturns.data['returns'] as num).toDouble();
      final weekRet = (weekReturns.data['returns'] as num).toDouble();
      final weekCnt = (weekReturns.data['cnt'] as int?) ?? 0;
      final avgDailyReturns = weekCnt > 0 ? weekRet / 7 : 0.0;

      return {
        'today_sales': sales,
        'today_returns': returns,
        'today_rate': sales > 0 ? (returns / sales) * 100 : 0.0,
        'avg_daily_returns': avgDailyReturns,
      };
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchReturnRateComparison: $e\n$st');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> fetchOverdueDebts({double minBalance = 50}) async {
    try {
      final rows = await _db.customSelect(
        '''SELECT ca.customer_id AS id, c.name,
                  ca.current_balance AS balance
           FROM customer_accounts ca
           JOIN customers c ON c.id = ca.customer_id
           WHERE ca.current_balance >= ?
           ORDER BY ca.current_balance DESC
           LIMIT 15''',
        variables: [Variable(minBalance)],
        readsFrom: {_db.customerAccounts, _db.customers},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchOverdueDebts: $e\n$st');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchSalesComparisonToday() async {
    try {
      final today = _startOfDay(DateTime.now());
      final yesterday = today.subtract(const Duration(days: 1));
      final tomorrow = _endExclusive(DateTime.now());

      final rows = await _db.customSelect(
        '''SELECT
             COALESCE(SUM(CASE WHEN sale_date >= ? AND sale_date < ? THEN total END), 0) AS today_sales,
             COALESCE(SUM(CASE WHEN sale_date >= ? AND sale_date < ? THEN total END), 0) AS yesterday_sales,
             COALESCE(COUNT(CASE WHEN sale_date >= ? AND sale_date < ? THEN 1 END), 0) AS today_count
           FROM sales_invoices
           WHERE IFNULL(invoice_status, 'completed') != 'returned' ''',
        variables: [
          Variable(today),
          Variable(tomorrow),
          Variable(yesterday),
          Variable(today),
          Variable(today),
          Variable(tomorrow),
        ],
        readsFrom: {_db.salesInvoices},
      ).getSingle();
      return rows.data;
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchSalesComparisonToday: $e\n$st');
      return {};
    }
  }

  Future<int> fetchCriticalActivityCountToday() async {
    try {
      final today = _startOfDay(DateTime.now());
      final row = await _db.customSelect(
        '''SELECT COUNT(*) AS cnt FROM activity_logs
           WHERE created_at >= ?
             AND severity IN ('critical', 'warning')''',
        variables: [Variable(today)],
        readsFrom: {_db.activityLogs},
      ).getSingle();
      return (row.data['cnt'] as int?) ?? 0;
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchCriticalActivityCountToday: $e\n$st');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> fetchSuspiciousActivitySignals() async {
    try {
      final today = _startOfDay(DateTime.now());
      final rows = await _db.customSelect(
        '''SELECT user_id, username_snapshot AS name,
                  activity_type, action, COUNT(*) AS cnt
           FROM activity_logs
           WHERE created_at >= ?
             AND (
               action IN ('delete', 'void', 'cancel')
               OR activity_type LIKE '%void%'
               OR activity_type LIKE '%delete%'
             )
           GROUP BY user_id, activity_type, action
           HAVING cnt >= 3
           ORDER BY cnt DESC
           LIMIT 15''',
        variables: [Variable(today)],
        readsFrom: {_db.activityLogs},
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchSuspiciousActivitySignals: $e\n$st');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchCashierBehaviorRows() async {
    try {
      final today = _startOfDay(DateTime.now());
      final tomorrow = _endExclusive(DateTime.now());
      final startMs = today.millisecondsSinceEpoch;
      final endMs = tomorrow.millisecondsSinceEpoch;

      final rows = await _db.customSelect(
        '''SELECT u.id AS user_id,
                  COALESCE(u.username, u.full_name, 'مستخدم') AS name,
                  COALESCE(inv_stats.invoice_count, 0) AS invoice_count,
                  COALESCE(inv_stats.avg_invoice, 0) AS avg_invoice,
                  COALESCE(inv_stats.discount_invoices, 0) AS discount_invoices,
                  COALESCE(ret.refund_count, 0) AS refund_count,
                  COALESCE(ret.refund_amount, 0) AS refund_amount,
                  COALESCE(sess.mismatch_count, 0) AS session_mismatch_count,
                  COALESCE(sess.total_minutes, 0) AS session_minutes
           FROM users u
           LEFT JOIN (
             SELECT created_by_user_id AS uid,
                    COUNT(*) AS invoice_count,
                    AVG(total) AS avg_invoice,
                    SUM(CASE WHEN discount_amount > 0 THEN 1 ELSE 0 END) AS discount_invoices
             FROM sales_invoices
             WHERE sale_date >= ? AND sale_date < ?
               AND IFNULL(invoice_status, 'completed') != 'returned'
             GROUP BY created_by_user_id
           ) inv_stats ON inv_stats.uid = u.id
           LEFT JOIN (
             SELECT cashier_user_id AS uid,
                    COUNT(*) AS refund_count,
                    COALESCE(SUM(returned_amount), 0) AS refund_amount
             FROM return_audit_logs
             WHERE created_at >= ? AND created_at < ?
             GROUP BY cashier_user_id
           ) ret ON ret.uid = u.id
           LEFT JOIN (
             SELECT closed_by_user_id AS uid,
                    COUNT(CASE WHEN ABS(COALESCE(cash_difference, 0)) >= 5 THEN 1 END) AS mismatch_count,
                    COALESCE(SUM(
                      (julianday(closed_at) - julianday(opened_at)) * 24 * 60
                    ), 0) AS total_minutes
             FROM pos_sessions
             WHERE opened_at >= ? AND opened_at < ? AND is_closed = 1
             GROUP BY closed_by_user_id
           ) sess ON sess.uid = u.id
           WHERE u.is_active = 1
             AND (
               inv_stats.invoice_count > 0
               OR ret.refund_count > 0
               OR sess.mismatch_count > 0
             )
           ORDER BY ret.refund_amount DESC
           LIMIT 30''',
        variables: [
          Variable(today),
          Variable(tomorrow),
          Variable.withInt(startMs),
          Variable.withInt(endMs),
          Variable(today),
          Variable(tomorrow),
        ],
        readsFrom: {
          _db.usersTable,
          _db.salesInvoices,
          _db.returnAuditLogs,
          _db.posSessions,
        },
      ).get();
      return rows.map((r) => r.data).toList();
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchCashierBehaviorRows: $e\n$st');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchDailyClosingMetrics(DateTime date) async {
    try {
      final start = _startOfDay(date);
      final end = _endExclusive(date);
      final startMs = start.millisecondsSinceEpoch;
      final endMs = end.millisecondsSinceEpoch;

      final sales = await _db.customSelect(
        '''SELECT COALESCE(SUM(total), 0) AS total, COUNT(*) AS cnt
           FROM sales_invoices
           WHERE sale_date >= ? AND sale_date < ?
             AND IFNULL(invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).getSingle();

      final returns = await _db.customSelect(
        '''SELECT COALESCE(SUM(returned_amount), 0) AS total
           FROM return_audit_logs
           WHERE created_at >= ? AND created_at < ?''',
        variables: [Variable.withInt(startMs), Variable.withInt(endMs)],
        readsFrom: {_db.returnAuditLogs},
      ).getSingle();

      final debts = await _db.customSelect(
        '''SELECT
             (SELECT COALESCE(SUM(current_balance), 0) FROM customer_accounts) AS receivable,
             (SELECT COALESCE(SUM(current_balance), 0) FROM supplier_accounts) AS payable''',
        readsFrom: {_db.customerAccounts, _db.supplierAccounts},
      ).getSingle();

      final topProduct = await _db.customSelect(
        '''SELECT p.name, SUM(si.quantity) AS qty
           FROM sale_items si
           JOIN products p ON p.id = si.product_id
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY si.product_id
           ORDER BY qty DESC
           LIMIT 1''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.saleItems, _db.products, _db.salesInvoices},
      ).getSingleOrNull();

      final weakCategory = await _db.customSelect(
        '''SELECT c.name, COALESCE(SUM(si.total), 0) AS revenue
           FROM categories c
           LEFT JOIN products p ON p.category_id = c.id
           LEFT JOIN sale_items si ON si.product_id = p.id
           LEFT JOIN sales_invoices inv ON inv.id = si.invoice_id
             AND inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY c.id
           ORDER BY revenue ASC
           LIMIT 1''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {
          _db.categories,
          _db.products,
          _db.saleItems,
          _db.salesInvoices,
        },
      ).getSingleOrNull();

      final topCashier = await _db.customSelect(
        '''SELECT COALESCE(u.username, u.full_name, 'كاشير') AS name,
                  COALESCE(SUM(inv.total), 0) AS sales
           FROM sales_invoices inv
           JOIN users u ON u.id = inv.created_by_user_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY u.id
           ORDER BY sales DESC
           LIMIT 1''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices, _db.usersTable},
      ).getSingleOrNull();

      final mismatches = await _db.customSelect(
        '''SELECT COUNT(*) AS cnt FROM pos_sessions
           WHERE is_closed = 1
             AND closed_at >= ?
             AND ABS(COALESCE(cash_difference, 0)) >= 5''',
        variables: [Variable(start)],
        readsFrom: {_db.posSessions},
      ).getSingle();

      return {
        'total_sales': (sales.data['total'] as num).toDouble(),
        'invoice_count': (sales.data['cnt'] as int?) ?? 0,
        'total_returns': (returns.data['total'] as num).toDouble(),
        'receivable': (debts.data['receivable'] as num).toDouble(),
        'payable': (debts.data['payable'] as num).toDouble(),
        'top_product': topProduct?.data['name'] as String?,
        'weak_category': weakCategory?.data['name'] as String?,
        'top_cashier': topCashier?.data['name'] as String?,
        'session_mismatch_count': (mismatches.data['cnt'] as int?) ?? 0,
      };
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchDailyClosingMetrics: $e\n$st');
      return {};
    }
  }

  Future<double> fetchInventoryValueChangeWeek() async {
    try {
      final now = DateTime.now();
      final weekAgo = _startOfDay(now).subtract(const Duration(days: 7));
      final rows = await _db.customSelect(
        '''SELECT COALESCE(SUM(
             CASE WHEN current_stock < 0 THEN 0 ELSE current_stock END * cost_price
           ), 0) AS value
           FROM products WHERE is_active = 1''',
        readsFrom: {_db.products},
      ).getSingle();
      final current = (rows.data['value'] as num).toDouble();

      final soldCost = await _db.customSelect(
        '''SELECT COALESCE(SUM(si.quantity * COALESCE(si.unit_cost, 0)), 0) AS cost
           FROM sale_items si
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(weekAgo)],
        readsFrom: {_db.saleItems, _db.salesInvoices},
      ).getSingle();
      final weekCost = (soldCost.data['cost'] as num).toDouble();
      return current - weekCost;
    } catch (e, st) {
      debugPrint('[OperationsIntelligenceRepository] fetchInventoryValueChangeWeek: $e\n$st');
      return 0;
    }
  }
}
