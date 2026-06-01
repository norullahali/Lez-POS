// lib/features/returns/repositories/return_analytics_repository.dart
//
// READ-ONLY analytics repository for the return_audit_logs table.
// All queries are SELECT-only. No data is ever modified here.
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../models/return_analytics_models.dart';
import '../utils/return_analytics_date_utils.dart';

class _SqlFilter {
  const _SqlFilter(this.clause, this.variables);
  final String clause;
  final List<Variable> variables;
}

class ReturnAnalyticsRepository {
  final AppDatabase _db;
  ReturnAnalyticsRepository(this._db);

  // ---- helpers --------------------------------------------------------------

  _SqlFilter _whereFilter(ReturnAnalyticsFilter f, {String prefix = ''}) {
    final parts = <String>[];
    final vars = <Variable>[];
    final p = prefix.isEmpty ? '' : '$prefix.';

    if (f.fromDate != null) {
      parts.add('${p}created_at >= ?');
      vars.add(Variable.withInt(ReturnAnalyticsDateUtils.startMs(f.fromDate!)));
    }
    if (f.toDate != null) {
      parts.add('${p}created_at <= ?');
      vars.add(Variable.withInt(ReturnAnalyticsDateUtils.endMs(f.toDate!)));
    }
    if (f.cashierUserId != null) {
      parts.add('${p}cashier_user_id = ?');
      vars.add(Variable.withInt(f.cashierUserId!));
    }
    if (f.returnType != null) {
      parts.add('${p}return_type = ?');
      vars.add(Variable.withString(f.returnType!));
    }
    if (f.productId != null) {
      parts.add('${p}product_id = ?');
      vars.add(Variable.withInt(f.productId!));
    }

    if (parts.isEmpty) return const _SqlFilter('', []);
    return _SqlFilter('WHERE ${parts.join(' AND ')}', vars);
  }

  String _appendSince(String baseClause, List<Variable> baseVars, int sinceMs) {
    // Used by overview time-bucket queries; baseClause may already contain WHERE.
    return baseClause.isEmpty
        ? 'WHERE created_at >= ?'
        : '$baseClause AND created_at >= ?';
  }

  int get _todayMs => ReturnAnalyticsDateUtils.todayStartMs;

  int get _weekStartMs => ReturnAnalyticsDateUtils.weekStartMs;

  int get _monthStartMs => ReturnAnalyticsDateUtils.monthStartMs;

  // ---- Overview -------------------------------------------------------------

  Future<ReturnOverview> getOverview(ReturnAnalyticsFilter f) async {
    final filter = _whereFilter(f);

    final mainRows = await _db.customSelect(
      '''SELECT
          COUNT(*)                                           AS total_count,
          COALESCE(SUM(returned_amount), 0)                 AS total_amount,
          COUNT(CASE WHEN return_type = 'full'    THEN 1 END) AS full_count,
          COUNT(CASE WHEN return_type = 'partial' THEN 1 END) AS partial_count,
          COUNT(CASE WHEN return_type = 'smart_lookup' THEN 1 END) AS smart_lookup_count,
          COUNT(DISTINCT cashier_user_id)                    AS unique_cashiers,
          COUNT(DISTINCT product_id)                         AS unique_products
        FROM return_audit_logs
        ${filter.clause}''',
      variables: filter.variables,
      readsFrom: {_db.returnAuditLogs},
    ).get();

    Future<Map<String, dynamic>> timeAgg(int since) async {
      final clause = _appendSince(filter.clause, filter.variables, since);
      final vars = [...filter.variables, Variable.withInt(since)];
      final rows = await _db.customSelect(
        '''SELECT COUNT(*) AS cnt, COALESCE(SUM(returned_amount), 0) AS amt
           FROM return_audit_logs $clause''',
        variables: vars,
        readsFrom: {_db.returnAuditLogs},
      ).get();
      return rows.isNotEmpty ? rows.first.data : <String, dynamic>{};
    }

    final todayData = await timeAgg(_todayMs);
    final weekData = await timeAgg(_weekStartMs);
    final monthData = await timeAgg(_monthStartMs);

    final main = mainRows.isNotEmpty ? mainRows.first.data : <String, dynamic>{};

    return ReturnOverview(
      totalCount: (main['total_count'] as int?) ?? 0,
      totalAmount: ((main['total_amount'] as num?) ?? 0).toDouble(),
      fullCount: (main['full_count'] as int?) ?? 0,
      partialCount: (main['partial_count'] as int?) ?? 0,
      smartLookupCount: (main['smart_lookup_count'] as int?) ?? 0,
      uniqueCashiers: (main['unique_cashiers'] as int?) ?? 0,
      uniqueProductsReturned: (main['unique_products'] as int?) ?? 0,
      todayCount: (todayData['cnt'] as int?) ?? 0,
      todayAmount: ((todayData['amt'] as num?) ?? 0).toDouble(),
      weekCount: (weekData['cnt'] as int?) ?? 0,
      weekAmount: ((weekData['amt'] as num?) ?? 0).toDouble(),
      monthCount: (monthData['cnt'] as int?) ?? 0,
      monthAmount: ((monthData['amt'] as num?) ?? 0).toDouble(),
    );
  }

  // ---- Filter dropdown options --------------------------------------------

  Future<List<AnalyticsFilterOption>> getCashierFilterOptions() async {
    final rows = await _db.customSelect(
      '''SELECT cashier_user_id AS id,
                COALESCE(cashier_name_snapshot, '—') AS label
         FROM return_audit_logs
         WHERE cashier_user_id IS NOT NULL
         GROUP BY cashier_user_id
         ORDER BY label ASC
         LIMIT 100''',
      readsFrom: {_db.returnAuditLogs},
    ).get();

    return rows
        .map((r) => AnalyticsFilterOption(
              id: (r.data['id'] as int?) ?? 0,
              label: r.data['label'] as String? ?? '—',
            ))
        .toList();
  }

  Future<List<AnalyticsFilterOption>> getProductFilterOptions() async {
    final rows = await _db.customSelect(
      '''SELECT ral.product_id AS id,
                COALESCE(p.name, 'منتج #' || COALESCE(ral.product_id, '?')) AS label
         FROM return_audit_logs ral
         LEFT JOIN products p ON p.id = ral.product_id
         WHERE ral.product_id IS NOT NULL
         GROUP BY ral.product_id
         ORDER BY label ASC
         LIMIT 200''',
      readsFrom: {_db.returnAuditLogs, _db.products},
    ).get();

    return rows
        .map((r) => AnalyticsFilterOption(
              id: (r.data['id'] as int?) ?? 0,
              label: r.data['label'] as String? ?? '—',
            ))
        .toList();
  }

  // ---- Daily trend (last 30 days or filtered range) -----------------------

  Future<List<ReturnTrendPoint>> getDailyTrend(ReturnAnalyticsFilter f) async {
    final effectiveFrom = f.fromDate ??
        DateTime.now().subtract(const Duration(days: 29));
    final effectiveTo = f.toDate ?? DateTime.now();
    final fromMs = ReturnAnalyticsDateUtils.startMs(effectiveFrom);
    final toMs = ReturnAnalyticsDateUtils.endMs(effectiveTo);

    final parts = <String>[
      'ral.created_at >= ?',
      'ral.created_at <= ?',
    ];
    final vars = <Variable>[
      Variable.withInt(fromMs),
      Variable.withInt(toMs),
    ];

    if (f.cashierUserId != null) {
      parts.add('ral.cashier_user_id = ?');
      vars.add(Variable.withInt(f.cashierUserId!));
    }
    if (f.returnType != null) {
      parts.add('ral.return_type = ?');
      vars.add(Variable.withString(f.returnType!));
    }
    if (f.productId != null) {
      parts.add('ral.product_id = ?');
      vars.add(Variable.withInt(f.productId!));
    }

    final where = 'WHERE ${parts.join(' AND ')}';

    final rows = await _db.customSelect(
      '''SELECT
          DATE(ral.created_at / 1000, 'unixepoch', 'localtime') AS day,
          COUNT(*)                                                AS cnt,
          COALESCE(SUM(ral.returned_amount), 0)                  AS amt
        FROM return_audit_logs ral
        $where
        GROUP BY day
        ORDER BY day ASC''',
      variables: vars,
      readsFrom: {_db.returnAuditLogs},
    ).get();

    return rows
        .map((r) => ReturnTrendPoint(
              day: r.data['day'] as String? ?? '',
              count: (r.data['cnt'] as int?) ?? 0,
              amount: ((r.data['amt'] as num?) ?? 0).toDouble(),
            ))
        .toList();
  }

  // ---- Top returned products ----------------------------------------------

  Future<List<TopReturnedProduct>> getTopProducts(
    ReturnAnalyticsFilter f, {
    int limit = 10,
  }) async {
    final filter = _whereFilter(f, prefix: 'ral');

    final rows = await _db.customSelect(
      '''SELECT
          ral.product_id,
          COALESCE(p.name, 'منتج #' || COALESCE(ral.product_id, '?')) AS product_name,
          COALESCE(SUM(ral.returned_quantity), 0) AS total_qty,
          COALESCE(SUM(ral.returned_amount), 0)   AS total_amt,
          COUNT(*) AS return_count
        FROM return_audit_logs ral
        LEFT JOIN products p ON p.id = ral.product_id
        ${filter.clause}
        GROUP BY ral.product_id
        ORDER BY total_amt DESC
        LIMIT $limit''',
      variables: filter.variables,
      readsFrom: {_db.returnAuditLogs, _db.products},
    ).get();

    return rows
        .map((r) => TopReturnedProduct(
              productId: r.data['product_id'] as int?,
              productName: r.data['product_name'] as String? ?? '—',
              totalQuantity:
                  ((r.data['total_qty'] as num?) ?? 0).toDouble(),
              totalAmount: ((r.data['total_amt'] as num?) ?? 0).toDouble(),
              returnCount: (r.data['return_count'] as int?) ?? 0,
            ))
        .toList();
  }

  // ---- Cashier analytics --------------------------------------------------

  Future<List<CashierReturnStat>> getCashierStats(
      ReturnAnalyticsFilter f) async {
    final filter = _whereFilter(f);

    final rows = await _db.customSelect(
      '''SELECT
          cashier_user_id,
          COALESCE(cashier_name_snapshot, '—') AS cashier_name,
          COUNT(*) AS total_returns,
          COALESCE(SUM(returned_amount), 0) AS total_amount,
          COUNT(CASE WHEN return_type = 'full'    THEN 1 END) AS full_count,
          COUNT(CASE WHEN return_type = 'partial' THEN 1 END) AS partial_count
        FROM return_audit_logs
        ${filter.clause}
        GROUP BY cashier_user_id
        ORDER BY total_returns DESC''',
      variables: filter.variables,
      readsFrom: {_db.returnAuditLogs},
    ).get();

    return rows
        .map((r) => CashierReturnStat(
              cashierUserId: r.data['cashier_user_id'] as int?,
              cashierName: r.data['cashier_name'] as String? ?? '—',
              totalReturns: (r.data['total_returns'] as int?) ?? 0,
              totalAmount:
                  ((r.data['total_amount'] as num?) ?? 0).toDouble(),
              fullReturns: (r.data['full_count'] as int?) ?? 0,
              partialReturns: (r.data['partial_count'] as int?) ?? 0,
            ))
        .toList();
  }

  // ---- Suspicious indicators (read-only rules engine) ---------------------

  Future<List<SuspiciousFlag>> getSuspiciousFlags() async {
    final flags = <SuspiciousFlag>[];
    final todayMs = _todayMs;

    final todayCountRows = await _db.customSelect(
      'SELECT COUNT(*) AS cnt FROM return_audit_logs WHERE created_at >= ?',
      variables: [Variable.withInt(todayMs)],
      readsFrom: {_db.returnAuditLogs},
    ).get();
    final todayCount = (todayCountRows.first.data['cnt'] as int?) ?? 0;
    if (todayCount >= 15) {
      flags.add(SuspiciousFlag(
        title: 'حجم مرتجعات مرتفع اليوم',
        description: 'تم تسجيل $todayCount عملية إرجاع اليوم. راجع الأنشطة.',
        severity: todayCount >= 30
            ? SuspiciousSeverity.high
            : SuspiciousSeverity.medium,
      ));
    }

    final cashierTodayRows = await _db.customSelect(
      '''SELECT cashier_user_id,
                COALESCE(cashier_name_snapshot,'—') AS name,
                COUNT(*) AS cnt
         FROM return_audit_logs
         WHERE created_at >= ?
         GROUP BY cashier_user_id
         HAVING cnt >= 8
         ORDER BY cnt DESC
         LIMIT 5''',
      variables: [Variable.withInt(todayMs)],
      readsFrom: {_db.returnAuditLogs},
    ).get();
    for (final r in cashierTodayRows) {
      final name = r.data['name'] as String? ?? '—';
      final cnt = (r.data['cnt'] as int?) ?? 0;
      final uid = r.data['cashier_user_id'] as int?;
      flags.add(SuspiciousFlag(
        title: 'كاشير بمرتجعات مفرطة اليوم',
        description: 'الكاشير "$name" أجرى $cnt مرتجعات اليوم.',
        severity: cnt >= 15 ? SuspiciousSeverity.high : SuspiciousSeverity.medium,
        relatedUserId: uid,
      ));
    }

    final sevenDaysAgo = ReturnAnalyticsDateUtils.startMs(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    final repeatedProductRows = await _db.customSelect(
      '''SELECT product_id,
                COALESCE(p.name,'منتج #' || COALESCE(ral.product_id,'?')) AS pname,
                COUNT(*) AS cnt
         FROM return_audit_logs ral
         LEFT JOIN products p ON p.id = ral.product_id
         WHERE ral.created_at >= ?
           AND ral.product_id IS NOT NULL
         GROUP BY ral.product_id
         HAVING cnt >= 5
         ORDER BY cnt DESC
         LIMIT 5''',
      variables: [Variable.withInt(sevenDaysAgo)],
      readsFrom: {_db.returnAuditLogs, _db.products},
    ).get();
    for (final r in repeatedProductRows) {
      final pname = r.data['pname'] as String? ?? '—';
      final cnt = (r.data['cnt'] as int?) ?? 0;
      final pid = r.data['product_id'] as int?;
      flags.add(SuspiciousFlag(
        title: 'منتج متكرر الإرجاع',
        description: 'المنتج "$pname" أُرجع $cnt مرة خلال 7 أيام.',
        severity: cnt >= 10 ? SuspiciousSeverity.high : SuspiciousSeverity.low,
        relatedProductId: pid,
      ));
    }

    final largeRows = await _db.customSelect(
      '''SELECT COALESCE(cashier_name_snapshot,'—') AS name,
                returned_amount,
                invoice_id
         FROM return_audit_logs
         WHERE created_at >= ?
           AND returned_amount > 500
         ORDER BY returned_amount DESC
         LIMIT 3''',
      variables: [Variable.withInt(todayMs)],
      readsFrom: {_db.returnAuditLogs},
    ).get();
    for (final r in largeRows) {
      final amt = ((r.data['returned_amount'] as num?) ?? 0).toDouble();
      final name = r.data['name'] as String? ?? '—';
      flags.add(SuspiciousFlag(
        title: 'إرجاع بمبلغ مرتفع',
        description:
            'الكاشير "$name" أجرى إرجاع بمبلغ ${amt.toStringAsFixed(0)} اليوم.',
        severity: amt >= 2000
            ? SuspiciousSeverity.high
            : SuspiciousSeverity.medium,
      ));
    }

    return flags;
  }

  // ---- Recent activity (paginated) ----------------------------------------

  Future<List<RecentAuditRow>> getRecentActivity({
    required ReturnAnalyticsFilter filter,
    int limit = 50,
    int offset = 0,
  }) async {
    final where = _whereFilter(filter, prefix: 'ral');

    final rows = await _db.customSelect(
      '''SELECT
          ral.id,
          ral.created_at,
          ral.return_type,
          ral.invoice_id,
          COALESCE(ral.cashier_name_snapshot, '—') AS cashier_name,
          COALESCE(p.name, '—')                    AS product_name,
          ral.returned_quantity,
          ral.returned_amount,
          ral.return_note,
          ral.return_reason
        FROM return_audit_logs ral
        LEFT JOIN products p ON p.id = ral.product_id
        ${where.clause}
        ORDER BY ral.created_at DESC
        LIMIT $limit OFFSET $offset''',
      variables: where.variables,
      readsFrom: {_db.returnAuditLogs, _db.products},
    ).get();

    return rows
        .map((r) => RecentAuditRow(
              id: (r.data['id'] as int?) ?? 0,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                  ReturnAnalyticsDateUtils.readTimestampMs(r.data['created_at'])),
              returnType: r.data['return_type'] as String? ?? '—',
              invoiceId: r.data['invoice_id'] as int?,
              cashierName: r.data['cashier_name'] as String? ?? '—',
              productName: r.data['product_name'] as String?,
              returnedQuantity:
                  ((r.data['returned_quantity'] as num?) ?? 0).toDouble(),
              returnedAmount:
                  ((r.data['returned_amount'] as num?) ?? 0).toDouble(),
              returnNote: r.data['return_note'] as String?,
              returnReason: r.data['return_reason'] as String?,
            ))
        .toList();
  }

  Future<int> getRecentActivityCount(ReturnAnalyticsFilter filter) async {
    final where = _whereFilter(filter, prefix: 'ral');
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS cnt FROM return_audit_logs ral ${where.clause}',
      variables: where.variables,
      readsFrom: {_db.returnAuditLogs},
    ).get();
    return (rows.first.data['cnt'] as int?) ?? 0;
  }
}
