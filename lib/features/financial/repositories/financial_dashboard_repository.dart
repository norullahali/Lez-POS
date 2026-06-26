import "package:drift/drift.dart";

import "../../../core/database/app_database.dart";

/// Read-only aggregation repository for dashboard KPIs that do NOT come from the
/// Cash Ledger UNION. Owns three categories of queries:
///
/// 1. Debt KPIs (always current, no date filter):
///    - customerDebt: SUM(customer_accounts.current_balance WHERE > 0)
///    - supplierDebt: SUM(supplier_accounts.current_balance WHERE > 0)
///
/// 2. Supplementary sales KPIs (period-filtered from sales_invoices):
///    - totalSales: SUM(total) -- ACCRUAL, includes credit/آجل sales
///    - cardSales:  SUM(card_paid)
///
/// 3. Session KPI (period-filtered from pos_sessions):
///    - sessionDifference: SUM(cash_difference WHERE is_closed = 1)
///
/// ARCHITECTURE RULES:
///   - This repository NEVER calls FinancialLedgerRepository.
///   - This repository NEVER duplicates Cash Ledger SQL.
///   - Provider orchestration belongs in dashboard_providers.dart.
///   - This repository is READ-ONLY -- no inserts, updates, or deletes.
class FinancialDashboardRepository {
  const FinancialDashboardRepository(this._db);

  final AppDatabase _db;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns the two always-current debt KPIs.
  /// Reads from [customer_accounts] and [supplier_accounts] balance caches.
  /// These are O(n customers/suppliers) aggregate scans -- fast and indexed.
  Future<({double customerDebt, double supplierDebt})> getCurrentState() async {
    // Run both DAO queries concurrently -- identical return values and behavior.
    final results = await Future.wait([
      _db.customerAccountsDao.getTotalOutstanding(),
      _db.supplierAccountsDao.getTotalOutstanding(),
    ]);
    return (customerDebt: results[0], supplierDebt: results[1]);
  }

  /// Returns the three period-filtered supplementary KPIs.
  /// [start] is inclusive (start of day). [end] is exclusive (start of next day).
  ///
  /// totalSales and cardSales read from [sales_invoices] filtered by [sale_date].
  /// sessionDifference reads from [pos_sessions] filtered by [closed_at] WHERE
  /// [is_closed] = 1. Open sessions are excluded.
  Future<({double totalSales, double cardSales, double sessionDifference})>
      getSupplementaryKpis({
    required DateTime start,
    required DateTime end,
  }) async {
    final salesFuture = _querySalesKpis(start, end);
    final sessionFuture = _querySessionKpi(start, end);
    final salesResult = await salesFuture;
    final sessionResult = await sessionFuture;
    return (
      totalSales: salesResult.totalSales,
      cardSales: salesResult.cardSales,
      sessionDifference: sessionResult,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<({double totalSales, double cardSales})> _querySalesKpis(
    DateTime start,
    DateTime end,
  ) async {
    try {
      const sql = '''
SELECT
  COALESCE(SUM(total), 0.0)    AS total_sales,
  COALESCE(SUM(card_paid), 0.0) AS card_sales
FROM sales_invoices
WHERE sale_date >= ? AND sale_date < ?
''';
      final row = await _db.customSelect(
        sql,
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.salesInvoices},
      ).getSingle();
      return (
        totalSales: (row.data['total_sales'] as num?)?.toDouble() ?? 0,
        cardSales: (row.data['card_sales'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return (totalSales: 0.0, cardSales: 0.0);
    }
  }

  Future<double> _querySessionKpi(DateTime start, DateTime end) async {
    try {
      // Filters: closed session, closed within period.
      // is_closed is stored as INTEGER 1/0 in SQLite (Drift boolean).
      const sql = '''
SELECT COALESCE(SUM(cash_difference), 0.0) AS session_diff
FROM pos_sessions
WHERE is_closed = 1
  AND closed_at >= ?
  AND closed_at < ?
''';
      final row = await _db.customSelect(
        sql,
        variables: [Variable(start), Variable(end)],
        readsFrom: {_db.posSessions},
      ).getSingle();
      return (row.data['session_diff'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0.0;
    }
  }
}