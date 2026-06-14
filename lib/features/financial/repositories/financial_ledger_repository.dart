import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../models/cash_ledger_event.dart';
import '../models/cash_ledger_event_type.dart';
import '../models/cash_ledger_filter.dart';
import '../models/cash_ledger_summary.dart';
import '../utils/cash_ledger_date_utils.dart';

/// Read-only derived cash ledger — UNION over operational tables (Hybrid Model).
class FinancialLedgerRepository {
  FinancialLedgerRepository(this._db);

  final AppDatabase _db;

  /// Core UNION — approved sources only; double-count guards embedded (Rules A–D).
  static const _unionSql = '''
SELECT
  'SALE_CASH:' || si.id AS ledger_id,
  si.sale_date AS event_ts,
  'SALE_CASH' AS event_type,
  si.cash_paid AS amount,
  'inflow' AS direction,
  'sales_invoice' AS reference_type,
  si.id AS reference_id,
  COALESCE(si.processed_by_user_id, si.created_by_user_id) AS user_id,
  si.customer_id AS customer_id,
  NULL AS supplier_id,
  si.id AS invoice_id,
  ('بيع نقدي — فاتورة ' || si.invoice_number) AS description
FROM sales_invoices si
WHERE si.cash_paid > 0

UNION ALL

SELECT
  'CUSTOMER_PAYMENT:' || ct.id,
  ct.created_at,
  'CUSTOMER_PAYMENT',
  ABS(ct.amount),
  'inflow',
  'customer_transaction',
  ct.id,
  NULL,
  ct.customer_id,
  NULL,
  ct.reference_id,
  COALESCE(NULLIF(ct.note, ''), 'تحصيل من عميل')
FROM customer_transactions ct
WHERE ct.type = 'PAYMENT'

UNION ALL

SELECT
  'PURCHASE_CASH:' || pi.id,
  pi.purchase_date,
  'PURCHASE_CASH',
  pi.paid_amount,
  'outflow',
  'purchase_invoice',
  pi.id,
  pi.created_by_user_id,
  NULL,
  pi.supplier_id,
  NULL,
  ('دفع مشتريات — فاتورة ' || COALESCE(NULLIF(pi.invoice_number, ''), '#' || pi.id))
FROM purchase_invoices pi
WHERE pi.paid_amount > 0

UNION ALL

SELECT
  'SUPPLIER_PAYMENT:' || st.id,
  st.created_at,
  'SUPPLIER_PAYMENT',
  ABS(st.amount),
  'outflow',
  'supplier_transaction',
  st.id,
  NULL,
  NULL,
  st.supplier_id,
  st.reference_id,
  COALESCE(NULLIF(st.note, ''), 'دفع مورد')
FROM supplier_transactions st
WHERE st.type = 'PAYMENT'
  AND NOT (
    st.reference_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM purchase_invoices pi2 WHERE pi2.id = st.reference_id
    )
  )

UNION ALL

SELECT
  'RETURN_REFUND:' || ral.id,
  ral.created_at,
  'RETURN_REFUND',
  ral.returned_amount,
  'outflow',
  'return_audit_log',
  ral.id,
  ral.cashier_user_id,
  ral.customer_id,
  NULL,
  ral.invoice_id,
  ('مرتجع — ' || COALESCE(ral.return_type, 'return'))
FROM return_audit_logs ral
WHERE ral.returned_amount > 0
  AND NOT EXISTS (
    SELECT 1
    FROM customer_transactions ct2
    INNER JOIN customer_returns cr ON cr.id = ct2.reference_id
    WHERE ct2.type = 'RETURN'
      AND ral.invoice_id IS NOT NULL
      AND cr.original_invoice_id = ral.invoice_id
  )
''';

  Future<CashLedgerSummary> getSummary(CashLedgerFilter filter) async {
    try {
      final range = filter.resolvedRange;
      final start = _startOfDay(range.start);
      final end = _endExclusive(range.end);
      final where = _buildWhereClause(filter, start, end);
      final sql = '''
SELECT
  COALESCE(SUM(CASE WHEN q.direction = 'inflow' THEN q.amount ELSE 0 END), 0) AS total_in,
  COALESCE(SUM(CASE WHEN q.direction = 'outflow' THEN q.amount ELSE 0 END), 0) AS total_out,
  COUNT(*) AS cnt
FROM ($_unionSql) q
${where.clause}
''';
      final row = await _db.customSelect(
        sql,
        variables: where.variables,
        readsFrom: _readSet(),
      ).getSingle();
      final totalIn = (row.data['total_in'] as num?)?.toDouble() ?? 0;
      final totalOut = (row.data['total_out'] as num?)?.toDouble() ?? 0;
      return CashLedgerSummary(
        totalInflow: totalIn,
        totalOutflow: totalOut,
        netCashFlow: totalIn - totalOut,
        transactionCount: (row.data['cnt'] as int?) ?? 0,
      );
    } catch (e) {
      return CashLedgerSummary.empty;
    }
  }

  Future<CashLedgerPage> getEntries(CashLedgerFilter filter) async {
    try {
      final range = filter.resolvedRange;
      final start = _startOfDay(range.start);
      final end = _endExclusive(range.end);
      final where = _buildWhereClause(filter, start, end);
      final countSql = 'SELECT COUNT(*) AS cnt FROM ($_unionSql) q ${where.clause}';
      final countRow = await _db.customSelect(
        countSql,
        variables: where.variables,
        readsFrom: _readSet(),
      ).getSingle();
      final totalCount = (countRow.data['cnt'] as int?) ?? 0;

      if (totalCount == 0) {
        return CashLedgerPage(
          entries: const [],
          totalCount: 0,
          page: filter.page,
          pageSize: filter.pageSize,
        );
      }

      final order = filter.sortDescending ? 'DESC' : 'ASC';
      final offset = filter.page * filter.pageSize;
      final dataSql = '''
SELECT
  q.ledger_id,
  q.event_ts,
  q.event_type,
  q.amount,
  q.direction,
  q.reference_type,
  q.reference_id,
  q.user_id,
  q.customer_id,
  q.supplier_id,
  q.invoice_id,
  q.description,
  SUM(CASE WHEN q.direction = 'inflow' THEN q.amount ELSE -q.amount END)
    OVER (ORDER BY q.event_ts ASC, q.ledger_id ASC) AS running_balance
FROM ($_unionSql) q
${where.clause}
ORDER BY q.event_ts $order, q.ledger_id $order
LIMIT ${filter.pageSize} OFFSET $offset
''';
      final rows = await _db.customSelect(
        dataSql,
        variables: where.variables,
        readsFrom: _readSet(),
      ).get();

      final entries = rows.map(_mapRow).toList();
      return CashLedgerPage(
        entries: entries,
        totalCount: totalCount,
        page: filter.page,
        pageSize: filter.pageSize,
      );
    } catch (e) {
      return CashLedgerPage.empty;
    }
  }

  /// All entries in range for CSV export (capped).
  Future<List<CashLedgerEvent>> getEntriesForExport(
    CashLedgerFilter filter, {
    int maxRows = 10000,
  }) async {
    final exportFilter = filter.copyWith(
      page: 0,
      pageSize: maxRows,
      sortDescending: false,
    );
    final page = await getEntries(exportFilter);
    return page.entries;
  }

  CashLedgerEvent _mapRow(QueryRow row) {
    final data = row.data;
    final type = CashLedgerEventType.fromCode(data['event_type'] as String?) ??
        CashLedgerEventType.saleCash;
    final timestamp = CashLedgerDateUtils.parseEventTimestamp(data['event_ts']);
    return CashLedgerEvent(
      id: data['ledger_id'] as String? ?? '',
      timestamp: timestamp,
      eventType: type,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      direction: CashLedgerDirection.fromCode(data['direction'] as String? ?? 'inflow'),
      referenceType: data['reference_type'] as String? ?? '',
      referenceId: (data['reference_id'] as int?) ?? 0,
      userId: data['user_id'] as int?,
      customerId: data['customer_id'] as int?,
      supplierId: data['supplier_id'] as int?,
      invoiceId: data['invoice_id'] as int?,
      description: data['description'] as String? ?? '',
      runningBalance: (data['running_balance'] as num?)?.toDouble(),
    );
  }

  _WhereClause _buildWhereClause(
    CashLedgerFilter filter,
    DateTime start,
    DateTime end,
  ) {
    final variables = <Variable>[
      Variable(start),
      Variable(end),
    ];
    final parts = <String>['WHERE q.event_ts >= ?', 'q.event_ts < ?'];

    if (filter.eventType != null) {
      parts.add('q.event_type = ?');
      variables.add(Variable.withString(filter.eventType!.code));
    }

    final search = filter.searchQuery.trim();
    if (search.isNotEmpty) {
      parts.add("(q.description LIKE '%' || ? || '%' ESCAPE '\\' OR CAST(q.reference_id AS TEXT) LIKE '%' || ? || '%')");
      variables.add(Variable.withString(_escapeLike(search)));
      variables.add(Variable.withString(_escapeLike(search)));
    }

    return _WhereClause(clause: parts.join(' AND '), variables: variables);
  }

  static String _escapeLike(String input) =>
      input.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endExclusive(DateTime d) =>
      _startOfDay(d).add(const Duration(days: 1));

  Set<TableInfo> _readSet() => {
        _db.salesInvoices,
        _db.customerTransactions,
        _db.purchaseInvoices,
        _db.supplierTransactions,
        _db.returnAuditLogs,
        _db.customerReturns,
      };
}

class _WhereClause {
  const _WhereClause({required this.clause, required this.variables});
  final String clause;
  final List<Variable> variables;
}