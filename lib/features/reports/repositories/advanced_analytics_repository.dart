import 'package:drift/drift.dart' show Variable, QueryRow;
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/settings_service.dart';
import '../modules/shared/advanced_analytics_models.dart';

/// Read-only analytics queries for advanced report modules.
/// Does not modify existing DAOs.
class AdvancedAnalyticsRepository {
  AdvancedAnalyticsRepository(this._db);

  final AppDatabase _db;
  final SettingsService _settings = SettingsService(AppDatabase.instance);

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endExclusive(DateTime d) =>
      _startOfDay(d).add(const Duration(days: 1));

  // ---- Profit ----------------------------------------------------------------

  Future<ProfitAnalysisData> getProfitAnalysis(DateTime from, DateTime to) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);

      final summary = await _db.customSelect(
        '''SELECT
             COALESCE(SUM(si.total), 0) AS revenue,
             COALESCE(SUM(si.quantity * COALESCE(si.unit_cost, 0)), 0) AS cost
           FROM sale_items si
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.saleItems, _db.salesInvoices},
      ).getSingle();

      final revenue = (summary.data['revenue'] as num).toDouble();
      final cost = (summary.data['cost'] as num).toDouble();
      final profit = revenue - cost;
      final margin = revenue > 0 ? (profit / revenue) * 100 : 0.0;

      final topProfitable = await _db.customSelect(
        '''SELECT si.product_id AS product_id, p.name,
                  SUM(si.total) AS revenue,
                  SUM(si.quantity * COALESCE(si.unit_cost, 0)) AS cost,
                  SUM(si.total) - SUM(si.quantity * COALESCE(si.unit_cost, 0)) AS profit
           FROM sale_items si
           JOIN products p ON p.id = si.product_id
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY si.product_id
           HAVING profit > 0
           ORDER BY profit DESC
           LIMIT 10''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.saleItems, _db.salesInvoices, _db.products},
      ).get();

      final lowestMargin = await _db.customSelect(
        '''SELECT si.product_id AS product_id, p.name,
                  SUM(si.total) AS revenue,
                  SUM(si.quantity * COALESCE(si.unit_cost, 0)) AS cost,
                  SUM(si.total) - SUM(si.quantity * COALESCE(si.unit_cost, 0)) AS profit
           FROM sale_items si
           JOIN products p ON p.id = si.product_id
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY si.product_id
           HAVING revenue > 0
           ORDER BY (profit * 1.0 / revenue) ASC
           LIMIT 10''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.saleItems, _db.salesInvoices, _db.products},
      ).get();

      final trend = await _db.customSelect(
        '''SELECT strftime('%Y-%m-%d', inv.sale_date) AS day,
                  COALESCE(SUM(si.total), 0) AS revenue,
                  COALESCE(SUM(si.quantity * COALESCE(si.unit_cost, 0)), 0) AS cost
           FROM sale_items si
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY day
           ORDER BY day ASC
           LIMIT 90''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.saleItems, _db.salesInvoices},
      ).get();

      return ProfitAnalysisData(
        grossRevenue: revenue,
        estimatedCost: cost,
        grossProfit: profit,
        profitMarginPercent: margin,
        topProfitable: topProfitable.map(_mapProductProfit).toList(growable: false),
        lowestMargin: lowestMargin.map(_mapProductProfit).toList(growable: false),
        trend: trend
            .map((r) => AnalyticsTrendPoint(
                  label: r.data['day'] as String? ?? '',
                  primary: (r.data['revenue'] as num).toDouble(),
                  secondary: (r.data['cost'] as num).toDouble(),
                ))
            .toList(),
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getProfitAnalysis: $e\n$st');
      return ProfitAnalysisData.empty;
    }
  }

  ProductProfitRow _mapProductProfit(QueryRow r) {
    final revenue = (r.data['revenue'] as num?)?.toDouble() ?? 0;
    final profit = (r.data['profit'] as num?)?.toDouble() ?? 0;
    return ProductProfitRow(
      productId: r.data['product_id'] as int?,
      name: r.data['name'] as String? ?? '-',
      revenue: revenue,
      cost: (r.data['cost'] as num?)?.toDouble() ?? 0,
      profit: profit,
      marginPercent: revenue > 0 ? (profit / revenue) * 100 : 0,
    );
  }

  // ---- Cash flow -------------------------------------------------------------

  Future<CashFlowData> getCashFlow(DateTime from, DateTime to, {String groupBy = 'day'}) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);
      final groupExpr = switch (groupBy) {
        'week' => "strftime('%Y-W%W', inv.sale_date)",
        'month' => "strftime('%Y-%m', inv.sale_date)",
        _ => "strftime('%Y-%m-%d', inv.sale_date)",
      };

      final sales = await _db.customSelect(
        '''SELECT
             COALESCE(SUM(cash_paid), 0) AS cash_sales,
             COALESCE(SUM(card_paid), 0) AS card_sales
           FROM sales_invoices inv
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).getSingle();

      final customerCollections = await _db.customSelect(
        '''SELECT COALESCE(SUM(ABS(amount)), 0) AS total
           FROM customer_transactions
           WHERE type = 'PAYMENT' AND created_at >= ? AND created_at < ?''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.customerTransactions},
      ).getSingle();

      final supplierPayments = await _db.customSelect(
        '''SELECT COALESCE(SUM(ABS(amount)), 0) AS total
           FROM supplier_transactions
           WHERE type = 'PAYMENT' AND created_at >= ? AND created_at < ?''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.supplierTransactions},
      ).getSingle();

      final cashSales = (sales.data['cash_sales'] as num).toDouble();
      final cardSales = (sales.data['card_sales'] as num).toDouble();
      final collections = (customerCollections.data['total'] as num).toDouble();
      final payments = (supplierPayments.data['total'] as num).toDouble();
      const expenses = 0.0;

      final inflow = cashSales + cardSales + collections;
      final outflow = payments + expenses;

      final timeline = await _db.customSelect(
        '''SELECT $groupExpr AS period,
                  COALESCE(SUM(cash_paid + card_paid), 0) AS inflow
           FROM sales_invoices inv
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY period
           ORDER BY period ASC
           LIMIT 120''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).get();

      return CashFlowData(
        cashSales: cashSales,
        cardSales: cardSales,
        customerCollections: collections,
        supplierPayments: payments,
        expensesPlaceholder: expenses,
        totalInflow: inflow,
        totalOutflow: outflow,
        netCashFlow: inflow - outflow,
        timeline: timeline
            .map((r) => AnalyticsTrendPoint(
                  label: r.data['period'] as String? ?? '',
                  primary: (r.data['inflow'] as num).toDouble(),
                ))
            .toList(),
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getCashFlow: $e\n$st');
      return CashFlowData.empty;
    }
  }

  // ---- Return impact ---------------------------------------------------------

  Future<ReturnImpactData> getReturnImpact(DateTime from, DateTime to) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);
      final startMs = start.millisecondsSinceEpoch;
      final endMs = end.millisecondsSinceEpoch;

      final summary = await _db.customSelect(
        '''SELECT
             COUNT(*) AS return_count,
             COALESCE(SUM(returned_amount), 0) AS returned_amount,
             COUNT(CASE WHEN return_type = 'full' THEN 1 END) AS full_count,
             COUNT(CASE WHEN return_type = 'partial' THEN 1 END) AS partial_count
           FROM return_audit_logs
           WHERE created_at >= ? AND created_at < ?''',
        variables: [Variable.withInt(startMs), Variable.withInt(endMs)],
        readsFrom: {_db.returnAuditLogs},
      ).getSingle();

      final salesTotal = await _db.customSelect(
        '''SELECT COALESCE(SUM(total), 0) AS revenue
           FROM sales_invoices
           WHERE sale_date >= ? AND sale_date < ?
             AND IFNULL(invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).getSingle();

      final returned = (summary.data['returned_amount'] as num).toDouble();
      final revenue = (salesTotal.data['revenue'] as num).toDouble();
      final grossWithReturns = revenue + returned;
      final returnRate = grossWithReturns > 0 ? (returned / grossWithReturns) * 100 : 0.0;

      final topProducts = await _db.customSelect(
        '''SELECT product_id, COALESCE(p.name, 'منتج') AS name,
                  COUNT(*) AS cnt, COALESCE(SUM(returned_amount), 0) AS amount
           FROM return_audit_logs ral
           LEFT JOIN products p ON p.id = ral.product_id
           WHERE ral.created_at >= ? AND ral.created_at < ?
           GROUP BY product_id
           ORDER BY amount DESC
           LIMIT 10''',
        variables: [Variable.withInt(startMs), Variable.withInt(endMs)],
        readsFrom: {_db.returnAuditLogs, _db.products},
      ).get();

      final reasons = await _db.customSelect(
        '''SELECT COALESCE(return_reason, 'بدون سبب') AS reason, COUNT(*) AS cnt
           FROM return_audit_logs
           WHERE created_at >= ? AND created_at < ?
           GROUP BY return_reason
           ORDER BY cnt DESC
           LIMIT 10''',
        variables: [Variable.withInt(startMs), Variable.withInt(endMs)],
        readsFrom: {_db.returnAuditLogs},
      ).get();

      final trend = await _db.customSelect(
        '''SELECT strftime('%Y-%m-%d', datetime(created_at / 1000, 'unixepoch')) AS day,
                  COALESCE(SUM(returned_amount), 0) AS amount
           FROM return_audit_logs
           WHERE created_at >= ? AND created_at < ?
           GROUP BY day
           ORDER BY day ASC
           LIMIT 90''',
        variables: [Variable.withInt(startMs), Variable.withInt(endMs)],
        readsFrom: {_db.returnAuditLogs},
      ).get();

      return ReturnImpactData(
        totalReturnedAmount: returned,
        returnRatePercent: returnRate,
        netRevenueAfterReturns: revenue,
        fullReturnCount: (summary.data['full_count'] as int?) ?? 0,
        partialReturnCount: (summary.data['partial_count'] as int?) ?? 0,
        topReturnedProducts: topProducts
            .map((r) => RankedRow(
                  id: r.data['product_id'] as int?,
                  label: r.data['name'] as String? ?? '-',
                  count: (r.data['cnt'] as int?) ?? 0,
                  amount: (r.data['amount'] as num).toDouble(),
                ))
            .toList(),
        reasonFrequency: reasons
            .map((r) => LabelCount(
                  label: r.data['reason'] as String? ?? '-',
                  count: (r.data['cnt'] as int?) ?? 0,
                ))
            .toList(),
        trend: trend
            .map((r) => AnalyticsTrendPoint(
                  label: r.data['day'] as String? ?? '',
                  primary: (r.data['amount'] as num).toDouble(),
                ))
            .toList(),
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getReturnImpact: $e\n$st');
      return ReturnImpactData.empty;
    }
  }

  // ---- Inventory movement ----------------------------------------------------

  Future<InventoryMovementData> getInventoryMovement(DateTime from, DateTime to) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);

      final byType = await _db.customSelect(
        '''SELECT movement_type,
                  COALESCE(SUM(CASE WHEN quantity_change > 0 THEN quantity_change ELSE 0 END), 0) AS stock_in,
                  COALESCE(SUM(CASE WHEN quantity_change < 0 THEN ABS(quantity_change) ELSE 0 END), 0) AS stock_out
           FROM stock_movements
           WHERE created_at >= ? AND created_at < ?
           GROUP BY movement_type''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.stockMovements},
      ).get();

      final timeline = await _db.customSelect(
        '''SELECT strftime('%Y-%m-%d', created_at) AS day,
                  COALESCE(SUM(CASE WHEN quantity_change > 0 THEN quantity_change ELSE 0 END), 0) AS stock_in,
                  COALESCE(SUM(CASE WHEN quantity_change < 0 THEN ABS(quantity_change) ELSE 0 END), 0) AS stock_out
           FROM stock_movements
           WHERE created_at >= ? AND created_at < ?
           GROUP BY day
           ORDER BY day ASC
           LIMIT 90''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.stockMovements},
      ).get();

      final deadStock = await _db.customSelect(
        '''SELECT p.id AS product_id, p.name, p.current_stock,
                  COALESCE(p.cost_price, 0) AS cost,
                  (p.current_stock * COALESCE(p.cost_price, 0)) AS value
           FROM products p
           WHERE p.is_active = 1 AND p.current_stock > 0
             AND p.id NOT IN (
               SELECT DISTINCT si.product_id FROM sale_items si
               JOIN sales_invoices inv ON inv.id = si.invoice_id
               WHERE inv.sale_date >= ? AND inv.sale_date < ?
                 AND IFNULL(inv.invoice_status, 'completed') != 'returned'
             )
           ORDER BY value DESC
           LIMIT 20''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.products, _db.saleItems, _db.salesInvoices},
      ).get();

      double stockIn = 0, stockOut = 0, returnsIn = 0, adjustments = 0;
      for (final row in byType) {
        final type = row.data['movement_type'] as String? ?? '';
        final inn = (row.data['stock_in'] as num).toDouble();
        final out = (row.data['stock_out'] as num).toDouble();
        stockIn += inn;
        stockOut += out;
        if (type.contains('return') || type == 'full_return' || type == 'partial_return') {
          returnsIn += inn;
        }
        if (type.contains('adjust') || type == 'manual_adjustment') {
          adjustments += out + inn;
        }
      }

      return InventoryMovementData(
        stockIn: stockIn,
        stockOut: stockOut,
        returnsIn: returnsIn,
        adjustmentMovement: adjustments,
        deadInventoryCount: deadStock.length,
        turnoverEstimate: stockOut > 0 ? stockIn / stockOut : 0,
        byType: byType
            .map((r) => LabelAmountPair(
                  label: r.data['movement_type'] as String? ?? '-',
                  amount: (r.data['stock_in'] as num).toDouble() + (r.data['stock_out'] as num).toDouble(),
                ))
            .toList(),
        timeline: timeline
            .map((r) => AnalyticsTrendPoint(
                  label: r.data['day'] as String? ?? '',
                  primary: (r.data['stock_in'] as num).toDouble(),
                  secondary: (r.data['stock_out'] as num).toDouble(),
                ))
            .toList(),
        deadStock: deadStock
            .map((r) => DeadStockRow(
                  productId: r.data['product_id'] as int?,
                  name: r.data['name'] as String? ?? '-',
                  stock: (r.data['current_stock'] as num).toDouble(),
                  value: (r.data['value'] as num).toDouble(),
                ))
            .toList(),
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getInventoryMovement: $e\n$st');
      return InventoryMovementData.empty;
    }
  }

  // ---- Tax -------------------------------------------------------------------

  Future<TaxReportData> getTaxReport(DateTime from, DateTime to) async {
    try {
      final taxEnabled = await _settings.getShowTax();
      final start = _startOfDay(from);
      final end = _endExclusive(to);

      if (!taxEnabled) {
        return TaxReportData(
          taxEnabled: false,
          taxableSales: 0,
          estimatedTaxCollected: 0,
          taxExemptInvoices: 0,
          trend: const [],
        );
      }

      final row = await _db.customSelect(
        '''SELECT
             COALESCE(SUM(subtotal - discount_amount), 0) AS taxable_base,
             COUNT(*) AS invoice_count
           FROM sales_invoices
           WHERE sale_date >= ? AND sale_date < ?
             AND IFNULL(invoice_status, 'completed') != 'returned' ''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).getSingle();

      final taxable = (row.data['taxable_base'] as num).toDouble();
      final tax = taxable * 0.15;

      final trend = await _db.customSelect(
        '''SELECT strftime('%Y-%m-%d', sale_date) AS day,
                  COALESCE(SUM(subtotal - discount_amount), 0) AS taxable_base
           FROM sales_invoices
           WHERE sale_date >= ? AND sale_date < ?
             AND IFNULL(invoice_status, 'completed') != 'returned'
           GROUP BY day
           ORDER BY day ASC
           LIMIT 90''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).get();

      return TaxReportData(
        taxEnabled: true,
        taxableSales: taxable,
        estimatedTaxCollected: tax,
        taxExemptInvoices: 0,
        trend: trend
            .map((r) {
              final base = (r.data['taxable_base'] as num).toDouble();
              return AnalyticsTrendPoint(
                label: r.data['day'] as String? ?? '',
                primary: base * 0.15,
              );
            })
            .toList(),
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getTaxReport: $e\n$st');
      return TaxReportData.empty;
    }
  }

  // ---- Employee --------------------------------------------------------------

  Future<List<EmployeePerformanceRow>> getEmployeePerformance(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);
      final startMs = start.millisecondsSinceEpoch;
      final endMs = end.millisecondsSinceEpoch;

      final rows = await _db.customSelect(
        '''SELECT u.id AS user_id, COALESCE(u.username, u.full_name, 'مستخدم') AS name,
                  COUNT(inv.id) AS invoice_count,
                  COALESCE(SUM(inv.total), 0) AS sales_amount,
                  COALESCE(AVG(inv.total), 0) AS avg_invoice,
                  (SELECT COUNT(*) FROM return_audit_logs r
                     WHERE r.cashier_user_id = u.id
                       AND r.created_at >= ? AND r.created_at < ?) AS returns_handled,
                  (SELECT COALESCE(SUM(r.returned_amount), 0) FROM return_audit_logs r
                     WHERE r.cashier_user_id = u.id
                       AND r.created_at >= ? AND r.created_at < ?) AS refund_total,
                  (SELECT COALESCE(SUM(
                     (julianday(s.closed_at) - julianday(s.opened_at)) * 24 * 60
                   ), 0) FROM pos_sessions s
                     WHERE s.closed_by_user_id = u.id
                       AND s.opened_at >= ? AND s.opened_at < ?
                       AND s.is_closed = 1) AS session_minutes
           FROM sales_invoices inv
           JOIN users u ON u.id = inv.created_by_user_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY u.id
           ORDER BY sales_amount DESC
           LIMIT 50''',
        variables: [
          Variable.withInt(startMs),
          Variable.withInt(endMs),
          Variable.withInt(startMs),
          Variable.withInt(endMs),
          Variable(start),
          Variable(end),
          Variable(start),
          Variable(end),
        ],
        readsFrom: {
          _db.salesInvoices,
          _db.usersTable,
          _db.returnAuditLogs,
          _db.posSessions,
        },
      ).get();

      return rows
          .map((r) => EmployeePerformanceRow(
                userId: r.data['user_id'] as int,
                name: r.data['name'] as String? ?? '-',
                invoiceCount: (r.data['invoice_count'] as int?) ?? 0,
                salesAmount: (r.data['sales_amount'] as num).toDouble(),
                averageInvoice: (r.data['avg_invoice'] as num).toDouble(),
                returnsHandled: (r.data['returns_handled'] as int?) ?? 0,
                refundTotal: (r.data['refund_total'] as num).toDouble(),
                sessionMinutes: (r.data['session_minutes'] as num).toDouble(),
              ))
          .toList();
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getEmployeePerformance: $e\n$st');
      return [];
    }
  }

  // ---- Hourly ----------------------------------------------------------------

  Future<List<HourlySalesPoint>> getHourlySales(DateTime from, DateTime to) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);

      final rows = await _db.customSelect(
        '''SELECT CAST(strftime('%H', sale_date) AS INTEGER) AS hour,
                  COUNT(*) AS invoice_count,
                  COALESCE(SUM(total), 0) AS sales_amount
           FROM sales_invoices
           WHERE sale_date >= ? AND sale_date < ?
             AND IFNULL(invoice_status, 'completed') != 'returned'
           GROUP BY hour
           ORDER BY hour ASC''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).get();

      final map = {for (final r in rows) (r.data['hour'] as int): r.data};
      return List.generate(24, (h) {
        final data = map[h];
        return HourlySalesPoint(
          hour: h,
          invoiceCount: (data?['invoice_count'] as int?) ?? 0,
          salesAmount: ((data?['sales_amount'] as num?) ?? 0).toDouble(),
        );
      });
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getHourlySales: $e\n$st');
      return List.generate(24, (h) => HourlySalesPoint(hour: h, invoiceCount: 0, salesAmount: 0));
    }
  }

  // ---- Category --------------------------------------------------------------

  Future<List<CategoryPerformanceRow>> getCategoryPerformance(
    DateTime from,
    DateTime to,
  ) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);

      final rows = await _db.customSelect(
        '''SELECT COALESCE(c.id, 0) AS category_id,
                  COALESCE(c.name, 'بدون تصنيف') AS name,
                  COALESCE(SUM(si.quantity), 0) AS qty,
                  COALESCE(SUM(si.total), 0) AS revenue,
                  COALESCE(SUM(si.total - si.quantity * COALESCE(si.unit_cost, 0)), 0) AS profit
           FROM sale_items si
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           JOIN products p ON p.id = si.product_id
           LEFT JOIN categories c ON c.id = p.category_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY c.id
           ORDER BY revenue DESC
           LIMIT 30''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {
          _db.saleItems,
          _db.salesInvoices,
          _db.products,
          _db.categories,
        },
      ).get();

      final totalRevenue =
          rows.fold<double>(0, (s, r) => s + (r.data['revenue'] as num).toDouble());

      return rows
          .map((r) {
            final revenue = (r.data['revenue'] as num).toDouble();
            return CategoryPerformanceRow(
              categoryId: r.data['category_id'] as int?,
              name: r.data['name'] as String? ?? '-',
              quantitySold: (r.data['qty'] as num).toDouble(),
              revenue: revenue,
              profit: (r.data['profit'] as num).toDouble(),
              contributionPercent:
                  totalRevenue > 0 ? (revenue / totalRevenue) * 100 : 0,
            );
          })
          .toList();
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getCategoryPerformance: $e\n$st');
      return [];
    }
  }

  // ---- Product velocity ------------------------------------------------------

  Future<ProductVelocityData> getProductVelocity(DateTime from, DateTime to) async {
    try {
      final start = _startOfDay(from);
      final end = _endExclusive(to);

      final fast = await _db.customSelect(
        '''SELECT si.product_id, p.name,
                  SUM(si.quantity) AS qty, SUM(si.total) AS revenue
           FROM sale_items si
           JOIN products p ON p.id = si.product_id
           JOIN sales_invoices inv ON inv.id = si.invoice_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY si.product_id
           ORDER BY qty DESC
           LIMIT 15''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.saleItems, _db.products, _db.salesInvoices},
      ).get();

      final slow = await _db.customSelect(
        '''SELECT p.id AS product_id, p.name, p.current_stock,
                  COALESCE(SUM(si.quantity), 0) AS qty_sold,
                  julianday('now') - julianday(p.updated_at) AS age_days
           FROM products p
           LEFT JOIN sale_items si ON si.product_id = p.id
             AND si.invoice_id IN (
               SELECT id FROM sales_invoices
               WHERE sale_date >= ? AND sale_date < ?
                 AND IFNULL(invoice_status, 'completed') != 'returned'
             )
           WHERE p.is_active = 1 AND p.current_stock > 0
           GROUP BY p.id
           HAVING qty_sold <= 1
           ORDER BY p.current_stock DESC, age_days DESC
           LIMIT 15''',
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.products, _db.saleItems, _db.salesInvoices},
      ).get();

      return ProductVelocityData(
        fastMoving: fast
            .map((r) => VelocityRow(
                  productId: r.data['product_id'] as int?,
                  name: r.data['name'] as String? ?? '-',
                  quantity: (r.data['qty'] as num).toDouble(),
                  value: (r.data['revenue'] as num).toDouble(),
                  isDeadStock: false,
                ))
            .toList(),
        slowMoving: slow
            .map((r) {
              final qty = (r.data['qty_sold'] as num).toDouble();
              final stock = (r.data['current_stock'] as num).toDouble();
              return VelocityRow(
                productId: r.data['product_id'] as int?,
                name: r.data['name'] as String? ?? '-',
                quantity: qty,
                value: stock,
                isDeadStock: qty == 0 && stock > 0,
                ageDays: (r.data['age_days'] as num?)?.toDouble() ?? 0,
              );
            })
            .toList(),
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getProductVelocity: $e\n$st');
      return ProductVelocityData.empty;
    }
  }

  // ---- Executive -------------------------------------------------------------

  Future<ExecutiveDashboardData> getExecutiveDashboard(DateTime from, DateTime to) async {
    try {
      final profit = await getProfitAnalysis(from, to);
      final cash = await getCashFlow(from, to);
      final returns = await getReturnImpact(from, to);

      final inventory = await _db.customSelect(
        '''SELECT COALESCE(SUM(current_stock * cost_price), 0) AS value
           FROM products WHERE is_active = 1 AND current_stock > 0''',
        readsFrom: {_db.products},
      ).getSingle();

      final debts = await _db.customSelect(
        '''SELECT
             (SELECT COALESCE(SUM(current_balance), 0) FROM customer_accounts) AS receivable,
             (SELECT COALESCE(SUM(current_balance), 0) FROM supplier_accounts) AS payable''',
        readsFrom: {_db.customerAccounts, _db.supplierAccounts},
      ).getSingle();

      final topProduct = profit.topProfitable.isNotEmpty ? profit.topProfitable.first : null;

      final topCustomer = await _db.customSelect(
        '''SELECT c.id, c.name, COALESCE(SUM(inv.total), 0) AS spent
           FROM customers c
           JOIN sales_invoices inv ON inv.customer_id = c.id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY c.id
           ORDER BY spent DESC
           LIMIT 1''',
        variables: [Variable(_startOfDay(from)), Variable(_endExclusive(to))],
        readsFrom: {_db.customers, _db.salesInvoices},
      ).getSingleOrNull();

      final topCashier = await _db.customSelect(
        '''SELECT u.id, COALESCE(u.username, u.full_name) AS name,
                  COALESCE(SUM(inv.total), 0) AS sales
           FROM sales_invoices inv
           JOIN users u ON u.id = inv.created_by_user_id
           WHERE inv.sale_date >= ? AND inv.sale_date < ?
             AND IFNULL(inv.invoice_status, 'completed') != 'returned'
           GROUP BY u.id
           ORDER BY sales DESC
           LIMIT 1''',
        variables: [Variable(_startOfDay(from)), Variable(_endExclusive(to))],
        readsFrom: {_db.salesInvoices, _db.usersTable},
      ).getSingleOrNull();

      return ExecutiveDashboardData(
        totalRevenue: profit.grossRevenue,
        totalProfit: profit.grossProfit,
        netCashFlow: cash.netCashFlow,
        returnRatePercent: returns.returnRatePercent,
        inventoryValue: (inventory.data['value'] as num).toDouble(),
        receivableDebts: (debts.data['receivable'] as num).toDouble(),
        payableDebts: (debts.data['payable'] as num).toDouble(),
        topProductName: topProduct?.name,
        topCustomerName: topCustomer?.data['name'] as String?,
        topCashierName: topCashier?.data['name'] as String?,
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getExecutiveDashboard: $e\n$st');
      return ExecutiveDashboardData.empty;
    }
  }

  // ---- Comparative -----------------------------------------------------------

  Future<ComparativeAnalyticsData> getComparativeAnalytics(
    DateTime currentFrom,
    DateTime currentTo,
    DateTime previousFrom,
    DateTime previousTo,
  ) async {
    try {
      Future<PeriodMetrics> load(DateTime from, DateTime to) async {
        final profit = await getProfitAnalysis(from, to);
        final cash = await getCashFlow(from, to);
        final returns = await getReturnImpact(from, to);
        return PeriodMetrics(
          revenue: profit.grossRevenue,
          profit: profit.grossProfit,
          invoiceCount: 0,
          netCashFlow: cash.netCashFlow,
          returnRate: returns.returnRatePercent,
        );
      }

      final current = await load(currentFrom, currentTo);
      final previous = await load(previousFrom, previousTo);

      return ComparativeAnalyticsData(
        current: current,
        previous: previous,
        revenueChangePercent: _pctChange(previous.revenue, current.revenue),
        profitChangePercent: _pctChange(previous.profit, current.profit),
        cashFlowChangePercent: _pctChange(previous.netCashFlow, current.netCashFlow),
        returnRateChangePoints: current.returnRate - previous.returnRate,
      );
    } catch (e, st) {
      debugPrint('[AdvancedAnalyticsRepository] getComparativeAnalytics: $e\n$st');
      return ComparativeAnalyticsData.empty;
    }
  }

  double _pctChange(double previous, double current) {
    if (previous == 0) return current > 0 ? 100 : 0;
    return ((current - previous) / previous.abs()) * 100;
  }
}
