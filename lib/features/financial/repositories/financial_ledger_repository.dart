import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../models/cash_ledger_event.dart';
import '../models/cash_ledger_event_type.dart';
import '../models/cash_ledger_filter.dart';
import '../models/cash_ledger_summary.dart';
import '../models/dashboard_filter.dart';
import '../models/financial_dashboard_cash_analytics.dart';
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

-- Phase C Step 2.2: Customer cash refund — derived from customer_transactions REFUND rows.
-- One committed REFUND txn → exactly one CUSTOMER_REFUND outflow event.
-- Goods RETURN (type RETURN) is excluded; no double-count guard required.
SELECT
  'CUSTOMER_REFUND:' || ct.id,
  ct.created_at,
  'CUSTOMER_REFUND',
  ct.amount,
  'outflow',
  'customer_transaction',
  ct.id,
  NULL,
  ct.customer_id,
  NULL,
  cr.original_invoice_id,
  COALESCE(NULLIF(ct.note, ''), 'استرداد نقدي للعميل')
FROM customer_transactions ct
LEFT JOIN customer_returns cr ON cr.id = ct.reference_id
WHERE ct.type = 'REFUND'
  AND ct.amount > 0

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

-- SR.3.3: Supplier cash refund — derived from supplier_transactions REFUND rows.
-- One committed REFUND txn → exactly one SUPPLIER_REFUND inflow event.
-- Goods RETURN (type RETURN) is excluded; no double-count guard required.
SELECT
  'SUPPLIER_REFUND:' || st.id,
  st.created_at,
  'SUPPLIER_REFUND',
  st.amount,
  'inflow',
  'supplier_transaction',
  st.id,
  NULL,
  NULL,
  st.supplier_id,
  sr.purchase_invoice_id,
  COALESCE(NULLIF(st.note, ''), 'استرداد نقدي من مورد')
FROM supplier_transactions st
LEFT JOIN supplier_returns sr ON sr.id = st.reference_id
WHERE st.type = 'REFUND'
  AND st.amount > 0

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

UNION ALL

-- Phase 3.3: Operational expenses — derived from expense_records.
-- Section 3: expense_records is the sole source of truth; no ledger table created.
-- Section 4: is_voided = 0 — voided expenses are fully excluded (no reversal rows).
-- Section 6: No double-count guard required.
--   expense_records represent operational costs (overhead, utilities, wages, etc.)
--   They are INDEPENDENT of purchase_invoices (goods procurement) and
--   supplier_transactions (payment against purchase debt). Separate accounting objects.
--   One expense_record → exactly one EXPENSE ledger entry.
SELECT
  'EXPENSE:' || er.id,
  er.paid_at,
  'EXPENSE',
  er.amount,
  'outflow',
  'expense_record',
  er.id,
  er.created_by,
  NULL,
  NULL,
  NULL,
  COALESCE(
    (SELECT ec.name FROM expense_categories ec WHERE ec.id = er.category_id)
      || CASE WHEN NULLIF(TRIM(er.notes), '') IS NOT NULL
              THEN ' \u2014 ' || er.notes
              ELSE '' END,
    NULLIF(TRIM(er.notes), ''),
    '\u0645\u0635\u0631\u0648\u0641'
  )
FROM expense_records er
WHERE er.is_voided = 0
  AND er.amount > 0

UNION ALL

-- Phase 4.3: Other income — derived from other_income_records.
-- other_income_records is the sole source of truth; no ledger table created.
-- is_voided = 0 — voided records are fully excluded (no reversal rows).
-- No double-count guard required.
--   other_income_records represent non-sales cash inflows (commissions, rent, etc.)
--   They are INDEPENDENT of sales_invoices and customer_transactions.
--   One other_income_record → exactly one OTHER_INCOME ledger entry.
SELECT
  'OTHER_INCOME:' || oir.id,
  oir.received_at,
  'OTHER_INCOME',
  oir.amount,
  'inflow',
  'other_income_record',
  oir.id,
  oir.created_by,
  NULL,
  NULL,
  NULL,
  COALESCE(
    (SELECT oic.name FROM other_income_categories oic WHERE oic.id = oir.category_id)
      || CASE WHEN NULLIF(TRIM(oir.notes), '') IS NOT NULL
              THEN ' \u2014 ' || oir.notes
              ELSE '' END,
    NULLIF(TRIM(oir.notes), ''),
    '\u0625\u064a\u0631\u0627\u062f \u0622\u062e\u0631'
  )
FROM other_income_records oir
WHERE oir.is_voided = 0
  AND oir.amount > 0
''';

  /// All-time Cash Ledger net — no date filter, no event-type filter.
  /// Returns the accumulated cash balance since the first recorded ledger entry.
  /// Used by [dashboardCashBalanceProvider] (cached 45 s via keepAlive).
  /// Result label in UI: "الرصيد النقدي المحسوب".
  Future<CashLedgerSummary> getSummaryAllTime() async {
    try {
      const sql = '''
SELECT
  COALESCE(SUM(CASE WHEN q.direction = 'inflow' THEN q.amount ELSE 0 END), 0) AS total_in,
  COALESCE(SUM(CASE WHEN q.direction = 'outflow' THEN q.amount ELSE 0 END), 0) AS total_out,
  COUNT(*) AS cnt
FROM ($_unionSql) q
''';
      final row =
          await _db.customSelect(sql, readsFrom: _readSet()).getSingle();
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
      final row = await _db
          .customSelect(
            sql,
            variables: where.variables,
            readsFrom: _readSet(),
          )
          .getSingle();
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
      final countSql =
          'SELECT COUNT(*) AS cnt FROM ($_unionSql) q ${where.clause}';
      final countRow = await _db
          .customSelect(
            countSql,
            variables: where.variables,
            readsFrom: _readSet(),
          )
          .getSingle();
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
      final rows = await _db
          .customSelect(
            dataSql,
            variables: where.variables,
            readsFrom: _readSet(),
          )
          .get();

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

  static const _maxDailyBuckets = 31;
  static const _maxWeeklyBuckets = 26;
  static const _maxMonthlyBuckets = 12;

  /// Absolute tolerance when comparing bucket sums to [getSummary] scalars.
  ///
  /// Matches [CashLedgerSummary.isNetConsistent] (0.01) for floating-point safety.
  static const _totalsInvariantTolerance = 0.01;

  /// Bucketed inflow/outflow trend for dashboard charts.
  ///
  /// Wraps [_unionSql] and reuses [_buildWhereClause] — no duplicated UNION or
  /// filter logic.
  ///
  /// **Totals invariant:** for the same [filter], `SUM(buckets.inflow)` must
  /// equal [CashLedgerSummary.totalInflow] from [getSummary], and
  /// `SUM(buckets.outflow)` must equal [CashLedgerSummary.totalOutflow].
  /// Gap-filled zero buckets and bucket-cap merging preserve this invariant.
  /// See [verifyTimeSeriesTotalsInvariant].
  ///
  /// Direction CASE expressions must stay aligned with [getSummary].
  Future<FinancialDashboardCashFlowTimeSeries> getCashFlowTimeSeries(
    CashLedgerFilter filter,
    DashboardGranularity granularity,
  ) async {
    try {
      final range = filter.resolvedRange;
      final start = _startOfDay(range.start);
      final end = _endExclusive(range.end);
      final where = _buildWhereClause(filter, start, end);

      final (bucketSelect, bucketGroup, extraVariables) =
          _timeSeriesBucketSql(granularity, start);

      final variables = [...extraVariables, ...where.variables];
      final sql = '''
SELECT
  $bucketSelect AS bucket_key,
  COALESCE(SUM(CASE WHEN q.direction = 'inflow' THEN q.amount ELSE 0 END), 0) AS total_in,
  COALESCE(SUM(CASE WHEN q.direction = 'outflow' THEN q.amount ELSE 0 END), 0) AS total_out
FROM ($_unionSql) q
${where.clause}
GROUP BY $bucketGroup
ORDER BY bucket_key ASC
''';

      final rows = await _db
          .customSelect(
            sql,
            variables: variables,
            readsFrom: _readSet(),
          )
          .get();

      final totalsByKey = <String, (double inflow, double outflow)>{};
      for (final row in rows) {
        final key = _bucketKeyFromRow(row.data['bucket_key'], granularity);
        if (key == null) continue;
        totalsByKey[key] = (
          (row.data['total_in'] as num?)?.toDouble() ?? 0,
          (row.data['total_out'] as num?)?.toDouble() ?? 0,
        );
      }

      final labels = _generateBucketLabels(start, end, granularity);
      final buckets = _buildTimeSeriesBuckets(
        labels: labels,
        totalsByKey: totalsByKey,
        granularity: granularity,
      );

      return FinancialDashboardCashFlowTimeSeries(
        granularity: granularity,
        buckets: buckets,
      );
    } catch (_) {
      // Same silent .empty fallback as [getSummary] — callers receive empty series.
      return FinancialDashboardCashFlowTimeSeries.empty;
    }
  }

  /// Cash-flow composition grouped by [CashLedgerEventType].
  ///
  /// Wraps [_unionSql] and reuses [_buildWhereClause].
  Future<FinancialDashboardCashFlowBreakdown> getCashFlowBreakdownByEventType(
    CashLedgerFilter filter,
  ) async {
    try {
      final range = filter.resolvedRange;
      final start = _startOfDay(range.start);
      final end = _endExclusive(range.end);
      final where = _buildWhereClause(filter, start, end);
      final sql = '''
SELECT
  q.event_type AS event_type,
  q.direction AS direction,
  COALESCE(SUM(q.amount), 0) AS total_amount
FROM ($_unionSql) q
${where.clause}
GROUP BY q.event_type, q.direction
ORDER BY total_amount DESC
''';
      final rows = await _db
          .customSelect(
            sql,
            variables: where.variables,
            readsFrom: _readSet(),
          )
          .get();

      final slices = rows.map((row) {
        final type = CashLedgerEventType.fromCode(
              row.data['event_type'] as String?,
            ) ??
            CashLedgerEventType.saleCash;
        return FinancialDashboardBreakdownSlice(
          eventType: type,
          amount: (row.data['total_amount'] as num?)?.toDouble() ?? 0,
          direction: CashLedgerDirection.fromCode(
            row.data['direction'] as String? ??
                (type.isInflow
                    ? CashLedgerDirection.inflow.code
                    : CashLedgerDirection.outflow.code),
          ),
        );
      }).toList(growable: false);

      return FinancialDashboardCashFlowBreakdown(slices: slices);
    } catch (_) {
      // Same silent .empty fallback as [getSummary].
      return FinancialDashboardCashFlowBreakdown.empty;
    }
  }

  /// Validates the time-series totals invariant for [filter] and [granularity].
  ///
  /// Returns `true` when, within [_totalsInvariantTolerance]:
  /// - `SUM(bucket.inflow) == getSummary(filter).totalInflow`
  /// - `SUM(bucket.outflow) == getSummary(filter).totalOutflow`
  ///
  /// **Edge cases:**
  /// - Empty period / no rows: gap-filled zero buckets; both sides are 0 → `true`.
  /// - Single-day filter: one bucket carries the full period totals → `true`.
  /// - Long range with bucket-cap merge: merge sums adjacent keys without drop → `true`.
  /// - SQL failure: [getCashFlowTimeSeries] returns `.empty` (zero buckets);
  ///   if [getSummary] is non-zero, returns `false`.
  ///
  /// Intended for manual QA and future DB integration tests — not called in production UI.
  Future<bool> verifyTimeSeriesTotalsInvariant(
    CashLedgerFilter filter,
    DashboardGranularity granularity,
  ) async {
    final summary = await getSummary(filter);
    final series = await getCashFlowTimeSeries(filter, granularity);
    final sumInflow =
        series.buckets.fold<double>(0, (sum, b) => sum + b.inflow);
    final sumOutflow =
        series.buckets.fold<double>(0, (sum, b) => sum + b.outflow);
    return (sumInflow - summary.totalInflow).abs() <
            _totalsInvariantTolerance &&
        (sumOutflow - summary.totalOutflow).abs() < _totalsInvariantTolerance;
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
      direction: CashLedgerDirection.fromCode(
          data['direction'] as String? ?? 'inflow'),
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
      parts.add(
          "(q.description LIKE '%' || ? || '%' ESCAPE '\\' OR CAST(q.reference_id AS TEXT) LIKE '%' || ? || '%')");
      variables.add(Variable.withString(_escapeLike(search)));
      variables.add(Variable.withString(_escapeLike(search)));
    }

    return _WhereClause(clause: parts.join(' AND '), variables: variables);
  }

  static String _escapeLike(String input) => input
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  static int _maxBucketsFor(DashboardGranularity granularity) =>
      switch (granularity) {
        DashboardGranularity.day => _maxDailyBuckets,
        DashboardGranularity.week => _maxWeeklyBuckets,
        DashboardGranularity.month => _maxMonthlyBuckets,
      };

  static (String selectExpr, String groupExpr, List<Variable> extraVariables)
      _timeSeriesBucketSql(
          DashboardGranularity granularity, DateTime rangeStart) {
    return switch (granularity) {
      DashboardGranularity.day => (
          "strftime('%Y-%m-%d', q.event_ts)",
          "bucket_key",
          const <Variable>[],
        ),
      DashboardGranularity.week => (
          "CAST((julianday(date(q.event_ts)) - julianday(?)) / 7 AS INTEGER)",
          "bucket_key",
          [Variable(rangeStart)],
        ),
      DashboardGranularity.month => (
          "strftime('%Y-%m', q.event_ts)",
          "bucket_key",
          const <Variable>[],
        ),
    };
  }

  static String? _bucketKeyFromRow(
      Object? raw, DashboardGranularity granularity) {
    if (raw == null) return null;
    return switch (granularity) {
      DashboardGranularity.day => raw.toString(),
      DashboardGranularity.week => _weekLabelFromIndex((raw as num).toInt()),
      DashboardGranularity.month => raw.toString(),
    };
  }

  static String _weekLabelFromIndex(int bucketIndex) => 'week:$bucketIndex';

  /// Builds display buckets from pre-generated [labels] and SQL [totalsByKey].
  ///
  /// O(n) over label count; cap merge is a single linear pass (no nested scan).
  static List<FinancialDashboardTimeSeriesBucket> _buildTimeSeriesBuckets({
    required List<String> labels,
    required Map<String, (double inflow, double outflow)> totalsByKey,
    required DashboardGranularity granularity,
  }) {
    final maxBuckets = _maxBucketsFor(granularity);
    if (labels.length <= maxBuckets) {
      return labels.map((label) {
        final totals = totalsByKey[label];
        return FinancialDashboardTimeSeriesBucket(
          label: label,
          inflow: totals?.$1 ?? 0,
          outflow: totals?.$2 ?? 0,
        );
      }).toList(growable: false);
    }

    final chunkSize = (labels.length + maxBuckets - 1) ~/ maxBuckets;
    final buckets = <FinancialDashboardTimeSeriesBucket>[];
    for (var i = 0; i < labels.length; i += chunkSize) {
      final chunkEnd = (i + chunkSize).clamp(0, labels.length);
      final chunk = labels.sublist(i, chunkEnd);
      var inflow = 0.0;
      var outflow = 0.0;
      for (final label in chunk) {
        final totals = totalsByKey[label];
        if (totals != null) {
          inflow += totals.$1;
          outflow += totals.$2;
        }
      }
      buckets.add(
        FinancialDashboardTimeSeriesBucket(
          label: chunk.first,
          inflow: inflow,
          outflow: outflow,
        ),
      );
    }
    return buckets;
  }

  static List<String> _generateBucketLabels(
    DateTime start,
    DateTime endExclusive,
    DashboardGranularity granularity,
  ) {
    return switch (granularity) {
      DashboardGranularity.day => _generateDayLabels(start, endExclusive),
      DashboardGranularity.week => _generateWeekLabels(start, endExclusive),
      DashboardGranularity.month => _generateMonthLabels(start, endExclusive),
    };
  }

  static List<String> _generateDayLabels(
      DateTime start, DateTime endExclusive) {
    final labels = <String>[];
    var cursor = start;
    while (cursor.isBefore(endExclusive)) {
      labels.add(_formatDay(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return labels;
  }

  static List<String> _generateWeekLabels(
      DateTime start, DateTime endExclusive) {
    final labels = <String>[];
    final totalDays = endExclusive.difference(start).inDays;
    if (totalDays <= 0) return labels;
    final weekCount = (totalDays + 6) ~/ 7;
    for (var i = 0; i < weekCount; i++) {
      labels.add(_weekLabelFromIndex(i));
    }
    return labels;
  }

  static List<String> _generateMonthLabels(
    DateTime start,
    DateTime endExclusive,
  ) {
    final labels = <String>[];
    var cursor = DateTime(start.year, start.month);
    while (cursor.isBefore(endExclusive)) {
      labels.add(_formatMonth(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return labels;
  }

  static String _formatDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatMonth(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _endExclusive(DateTime d) =>
      _startOfDay(d).add(const Duration(days: 1));

  Set<TableInfo> _readSet() => {
        _db.salesInvoices,
        _db.customerTransactions,
        _db.purchaseInvoices,
        _db.supplierTransactions,
        _db.supplierReturns, // SR.3.3 — purchase invoice trace via return linkage
        _db.returnAuditLogs,
        _db.customerReturns,
        _db.expenseRecords, // Phase 3.3
        _db.expenseCategories, // Phase 3.3 — category name in description
        _db.otherIncomeRecords, // Phase 4.3
        _db.otherIncomeCategories, // Phase 4.3 — category name in description
      };
}

class _WhereClause {
  const _WhereClause({required this.clause, required this.variables});
  final String clause;
  final List<Variable> variables;
}
