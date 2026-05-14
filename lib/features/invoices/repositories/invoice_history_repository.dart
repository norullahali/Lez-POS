import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../data/invoice_history_query.dart';
import '../models/invoice_history_row.dart';

class InvoiceHistoryRepository {
  final AppDatabase _db;

  InvoiceHistoryRepository(this._db);

  static const _completedStatus = 'مكتملة';

  /// Distinct cashier display names (user full name or session cashier).
  Future<List<String>> listCashierNames() async {
    final rows = await _db.customSelect(
      '''
SELECT DISTINCT trim_key AS cashier_key FROM (
  SELECT TRIM(COALESCE(u.full_name, ps.cashier_name, '')) AS trim_key
  FROM sales_invoices si
  LEFT JOIN users u ON u.id = si.created_by_user_id
  LEFT JOIN pos_sessions ps ON ps.id = si.session_id
)
WHERE LENGTH(trim_key) > 0
ORDER BY trim_key COLLATE NOCASE
''',
      readsFrom: {
        _db.salesInvoices,
        _db.usersTable,
        _db.posSessions,
      },
    ).get();

    return rows
        .map((r) => r.data['cashier_key'] as String)
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  Future<InvoiceHistoryPage> fetchPage(InvoiceHistoryQuery q) async {
    final where = StringBuffer('WHERE 1=1');
    final variables = <Variable>[];

    final search = q.search.trim();
    if (search.isNotEmpty) {
      final safe = search.replaceAll('%', '').replaceAll('_', '');
      final like = '%$safe%';
      where.write(
        ' AND (si.invoice_number LIKE ? OR IFNULL(c.name, \'\') LIKE ?)',
      );
      variables.add(Variable.withString(like));
      variables.add(Variable.withString(like));
    }

    if (q.dateFrom != null) {
      final start = DateTime(q.dateFrom!.year, q.dateFrom!.month, q.dateFrom!.day);
      where.write(' AND si.sale_date >= ?');
      variables.add(Variable.withDateTime(start));
    }
    if (q.dateTo != null) {
      final endDay = DateTime(q.dateTo!.year, q.dateTo!.month, q.dateTo!.day)
          .add(const Duration(days: 1));
      where.write(' AND si.sale_date < ?');
      variables.add(Variable.withDateTime(endDay));
    }

    if (q.cashierName != null && q.cashierName!.trim().isNotEmpty) {
      where.write(
        ' AND TRIM(COALESCE(u.full_name, ps.cashier_name, \'\')) = ?',
      );
      variables.add(Variable.withString(q.cashierName!.trim()));
    }

    if (q.paymentMethod != null && q.paymentMethod!.isNotEmpty) {
      where.write(' AND si.payment_method = ?');
      variables.add(Variable.withString(q.paymentMethod!));
    }

    final joinFrom = '''
FROM sales_invoices si
LEFT JOIN customers c ON c.id = si.customer_id
LEFT JOIN users u ON u.id = si.created_by_user_id
LEFT JOIN pos_sessions ps ON ps.id = si.session_id
LEFT JOIN (
  SELECT invoice_id, COUNT(*) AS cnt FROM sale_items GROUP BY invoice_id
) ic ON ic.invoice_id = si.id
''';

    final countSql =
        'SELECT COUNT(*) AS cnt $joinFrom ${where.toString()}';
    final countRow = await _db.customSelect(
      countSql,
      variables: variables,
      readsFrom: {
        _db.salesInvoices,
        _db.saleItems,
        _db.customers,
        _db.usersTable,
        _db.posSessions,
      },
    ).getSingle();
    final totalCount = (countRow.data['cnt'] as num).toInt();

    final offset = q.page * q.pageSize;
    final dataSql = '''
SELECT
  si.id AS id,
  si.invoice_number AS invoice_number,
  si.sale_date AS sale_date,
  si.total AS total,
  si.payment_method AS payment_method,
  CASE
    WHEN si.customer_id IS NULL THEN 'زبون عام'
    ELSE IFNULL(c.name, 'زبون عام')
  END AS customer_name,
  TRIM(COALESCE(u.full_name, ps.cashier_name, '')) AS cashier_raw,
  COALESCE(ic.cnt, 0) AS item_count
$joinFrom
${where.toString()}
ORDER BY si.sale_date DESC, si.id DESC
LIMIT ? OFFSET ?
''';

    final dataVariables = [
      ...variables,
      Variable.withInt(q.pageSize),
      Variable.withInt(offset),
    ];

    final dataRows = await _db.customSelect(
      dataSql,
      variables: dataVariables,
      readsFrom: {
        _db.salesInvoices,
        _db.saleItems,
        _db.customers,
        _db.usersTable,
        _db.posSessions,
      },
    ).get();

    final rows = dataRows.map((r) {
      final rawCashier = r.data['cashier_raw'] as String? ?? '';
      final cashier =
          rawCashier.trim().isEmpty ? '—' : rawCashier.trim();

      final sd = r.data['sale_date'];
      final saleDate = sd is DateTime
          ? sd
          : DateTime.fromMillisecondsSinceEpoch((sd as num).toInt());

      return InvoiceHistoryRow(
        id: (r.data['id'] as num).toInt(),
        invoiceNumber: r.data['invoice_number'] as String,
        saleDate: saleDate,
        customerName: r.data['customer_name'] as String,
        cashierName: cashier,
        itemCount: (r.data['item_count'] as num?)?.toInt() ?? 0,
        total: (r.data['total'] as num).toDouble(),
        paymentMethod: r.data['payment_method'] as String? ?? '',
        status: _completedStatus,
      );
    }).toList();

    return InvoiceHistoryPage(
      rows: rows,
      totalCount: totalCount,
      page: q.page,
      pageSize: q.pageSize,
    );
  }
}
