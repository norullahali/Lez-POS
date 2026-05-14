import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/settings_service.dart';
import '../data/invoice_history_query.dart';
import '../models/invoice_detail.dart';
import '../models/invoice_history_row.dart';

class InvoiceHistoryRepository {
  InvoiceHistoryRepository(this._db);

  final AppDatabase _db;

  static const _completedStatus = 'مكتملة';

  static DateTime _parseSaleDate(dynamic raw) {
    if (raw == null) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    }
    if (raw is DateTime) {
      return raw.isUtc ? raw.toLocal() : raw;
    }
    if (raw is String) {
      return DateTime.parse(raw).toLocal();
    }
    if (raw is num) {
      final v = raw.toInt();
      const threshold = 100000000000;
      if (v.abs() < threshold) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
            .toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }
    throw ArgumentError('Unsupported sale_date type: ${raw.runtimeType}');
  }

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
      readsFrom: {_db.salesInvoices, _db.usersTable, _db.posSessions},
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
      final start =
          DateTime(q.dateFrom!.year, q.dateFrom!.month, q.dateFrom!.day);
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

    const joinFrom = '''
FROM sales_invoices si
LEFT JOIN customers c ON c.id = si.customer_id
LEFT JOIN users u ON u.id = si.created_by_user_id
LEFT JOIN pos_sessions ps ON ps.id = si.session_id
LEFT JOIN (
  SELECT invoice_id, COUNT(*) AS cnt FROM sale_items GROUP BY invoice_id
) ic ON ic.invoice_id = si.id
''';

    final countSql = 'SELECT COUNT(*) AS cnt $joinFrom ${where.toString()}';
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
      final cashier = rawCashier.trim().isEmpty ? '—' : rawCashier.trim();

      return InvoiceHistoryRow(
        id: (r.data['id'] as num).toInt(),
        invoiceNumber: r.data['invoice_number'] as String,
        saleDate: _parseSaleDate(r.data['sale_date']),
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

  Future<InvoiceDetailData> fetchInvoiceDetail(int invoiceId) async {
    final settings = SettingsService(_db);
    final showTax = await settings.getShowTax();

    final headerRows = await _db.customSelect(
      '''
SELECT
  si.id AS id,
  si.invoice_number AS invoice_number,
  si.sale_date AS sale_date,
  si.subtotal AS subtotal,
  si.discount_amount AS discount_amount,
  si.total AS total,
  si.payment_method AS payment_method,
  si.cash_paid AS cash_paid,
  si.card_paid AS card_paid,
  si.change_amount AS change_amount,
  CASE
    WHEN si.customer_id IS NULL THEN 'زبون عام'
    ELSE IFNULL(c.name, 'زبون عام')
  END AS customer_name,
  TRIM(COALESCE(u.full_name, ps.cashier_name, '')) AS cashier_raw
FROM sales_invoices si
LEFT JOIN customers c ON c.id = si.customer_id
LEFT JOIN users u ON u.id = si.created_by_user_id
LEFT JOIN pos_sessions ps ON ps.id = si.session_id
WHERE si.id = ?
''',
      variables: [Variable.withInt(invoiceId)],
      readsFrom: {
        _db.salesInvoices,
        _db.customers,
        _db.usersTable,
        _db.posSessions,
      },
    ).get();

    if (headerRows.isEmpty) {
      throw StateError('Invoice not found: $invoiceId');
    }

    final h = headerRows.first.data;
    final rawCashier = h['cashier_raw'] as String? ?? '';
    final cashier = rawCashier.trim().isEmpty ? '—' : rawCashier.trim();

    final header = InvoiceDetailHeader(
      id: (h['id'] as num).toInt(),
      invoiceNumber: h['invoice_number'] as String,
      saleDate: _parseSaleDate(h['sale_date']),
      customerName: h['customer_name'] as String,
      cashierName: cashier,
      paymentMethod: h['payment_method'] as String? ?? '',
      status: _completedStatus,
      subtotal: (h['subtotal'] as num).toDouble(),
      discountTotal: (h['discount_amount'] as num).toDouble(),
      total: (h['total'] as num).toDouble(),
      cashPaid: (h['cash_paid'] as num).toDouble(),
      cardPaid: (h['card_paid'] as num).toDouble(),
      changeAmount: (h['change_amount'] as num).toDouble(),
    );

    final lineRows = await _db.customSelect(
      '''
SELECT
  p.name AS product_name,
  s.quantity AS quantity,
  s.unit_price AS unit_price,
  s.discount_amount AS discount_amount,
  s.total AS line_total
FROM sale_items s
JOIN products p ON p.id = s.product_id
WHERE s.invoice_id = ?
ORDER BY s.id ASC
''',
      variables: [Variable.withInt(invoiceId)],
      readsFrom: {
        _db.saleItems,
        _db.products,
      },
    ).get();

    final lines = lineRows.map((r) {
      final m = r.data;
      return InvoiceDetailLine(
        productName: m['product_name'] as String,
        quantity: (m['quantity'] as num).toDouble(),
        unitPrice: (m['unit_price'] as num).toDouble(),
        discount: (m['discount_amount'] as num).toDouble(),
        lineTotal: (m['line_total'] as num).toDouble(),
      );
    }).toList();

    return InvoiceDetailData(
      header: header,
      lines: lines,
      showTax: showTax,
    );
  }
}
