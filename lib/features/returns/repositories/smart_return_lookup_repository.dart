// lib/features/returns/repositories/smart_return_lookup_repository.dart
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../models/smart_return_result.dart';

class SmartReturnLookupRepository {
  SmartReturnLookupRepository(this._db);

  final AppDatabase _db;

  static const int _maxResults = 60;

  static DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is DateTime) return raw.isUtc ? raw.toLocal() : raw;
    if (raw is String) return DateTime.parse(raw).toLocal();
    if (raw is num) {
      final v = raw.toInt();
      const threshold = 100000000000;
      if (v.abs() < threshold) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }
    return DateTime.now();
  }

  /// Searches historical sale-items matching [query] by:
  ///   - exact barcode
  ///   - partial barcode / product name
  ///   - customer phone
  ///   - invoice number
  ///
  /// Results are at the sale-item level.
  /// Fully-returned invoices (status='returned') are excluded.
  /// Items with no remaining returnable quantity are excluded.
  /// Ordered: exact barcode first, then most recent sale.
  Future<List<SmartReturnResult>> search(String query) async {
    final raw = query.trim();
    if (raw.isEmpty) return const [];

    // Sanitise for LIKE
    final safe = raw.replaceAll('%', '').replaceAll('_', '');
    final likeAny = '%$safe%';

    // Exact barcode variable used twice (WHERE + ORDER BY CASE)
    final rows = await _db.customSelect(
      '''
SELECT
  si.id                                                        AS invoice_id,
  si.invoice_number                                            AS invoice_number,
  si.sale_date                                                 AS sale_date,
  CASE
    WHEN si.customer_id IS NULL THEN 'زبون عام'
    ELSE IFNULL(c.name, 'زبون عام')
  END                                                          AS customer_name,
  TRIM(COALESCE(u.full_name, ps.cashier_name, ''))            AS cashier_raw,
  IFNULL(si.invoice_status, 'completed')                       AS invoice_status,
  sit.id                                                       AS sale_item_id,
  p.id                                                         AS product_id,
  p.name                                                       AS product_name,
  IFNULL(p.barcode, '')                                        AS barcode,
  sit.quantity                                                 AS sold_quantity,
  COALESCE(ret.returned_total, 0.0)                            AS already_returned,
  sit.unit_price                                               AS unit_price
FROM sale_items sit
JOIN  sales_invoices si ON si.id  = sit.invoice_id
JOIN  products       p  ON p.id   = sit.product_id
LEFT JOIN customers  c  ON c.id   = si.customer_id
LEFT JOIN users      u  ON u.id   = si.created_by_user_id
LEFT JOIN pos_sessions ps ON ps.id = si.session_id
LEFT JOIN (
  SELECT sale_item_id, SUM(returned_quantity) AS returned_total
  FROM   sale_item_returns
  GROUP  BY sale_item_id
) ret ON ret.sale_item_id = sit.id
WHERE
  IFNULL(si.invoice_status, 'completed') != 'returned'
  AND (sit.quantity - COALESCE(ret.returned_total, 0.0)) > 0
  AND (
        p.barcode        =    ?
     OR p.barcode        LIKE ?
     OR p.name           LIKE ?
     OR IFNULL(c.phone, '') LIKE ?
     OR si.invoice_number LIKE ?
  )
ORDER BY
  CASE WHEN p.barcode = ? THEN 0 ELSE 1 END,
  CASE WHEN IFNULL(c.phone, '') = ? THEN 0 ELSE 1 END,
  si.sale_date DESC,
  si.id        DESC
LIMIT ?
''',
      variables: [
        Variable.withString(raw),     // exact barcode =
        Variable.withString(likeAny), // barcode LIKE
        Variable.withString(likeAny), // name LIKE
        Variable.withString(likeAny), // phone LIKE
        Variable.withString(likeAny), // invoice_number LIKE
        Variable.withString(raw),     // ORDER BY barcode exact
        Variable.withString(raw),     // ORDER BY phone exact
        Variable.withInt(_maxResults),
      ],
      readsFrom: {
        _db.saleItems,
        _db.salesInvoices,
        _db.products,
        _db.customers,
        _db.usersTable,
        _db.posSessions,
        _db.saleItemReturns,
      },
    ).get();

    return rows.map((r) {
      final raw2 = r.data['cashier_raw'] as String? ?? '';
      return SmartReturnResult(
        invoiceId:       (r.data['invoice_id']    as num).toInt(),
        invoiceNumber:    r.data['invoice_number'] as String,
        saleDate:        _parseDate(r.data['sale_date']),
        customerName:     r.data['customer_name'] as String,
        cashierName:      raw2.trim().isEmpty ? '—' : raw2.trim(),
        invoiceStatus:    r.data['invoice_status'] as String,
        saleItemId:      (r.data['sale_item_id']   as num).toInt(),
        productId:       (r.data['product_id']     as num).toInt(),
        productName:      r.data['product_name']   as String,
        barcode:          r.data['barcode']        as String,
        soldQuantity:    (r.data['sold_quantity']   as num).toDouble(),
        alreadyReturned: (r.data['already_returned'] as num).toDouble(),
        unitPrice:       (r.data['unit_price']     as num).toDouble(),
      );
    }).toList();
  }
}