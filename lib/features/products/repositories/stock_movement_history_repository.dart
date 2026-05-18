// lib/features/products/repositories/stock_movement_history_repository.dart
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../models/stock_movement_row.dart';

class StockMovementHistoryRepository {
  StockMovementHistoryRepository(this._db);

  final AppDatabase _db;

  static DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.now();
    if (raw is DateTime) return raw.isUtc ? raw.toLocal() : raw;
    if (raw is String) return DateTime.parse(raw).toLocal();
    if (raw is num) {
      final v = raw.toInt();
      const threshold = 100000000000;
      if (v.abs() < threshold) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
            .toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
    }
    return DateTime.now();
  }

  Future<({List<StockMovementRow> rows, int totalCount})> getPagedMovements({
    required int productId,
    required int page,
    required int pageSize,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? movementType,
  }) async {
    final whereParts = <String>['sm.product_id = ?'];
    final baseVars = <Variable<Object>>[Variable.withInt(productId)];

    if (dateFrom != null) {
      whereParts.add('sm.created_at >= ?');
      baseVars.add(Variable.withDateTime(
          DateTime(dateFrom.year, dateFrom.month, dateFrom.day)));
    }
    if (dateTo != null) {
      whereParts.add('sm.created_at < ?');
      baseVars.add(Variable.withDateTime(
          DateTime(dateTo.year, dateTo.month, dateTo.day)
              .add(const Duration(days: 1))));
    }
    if (movementType != null && movementType.isNotEmpty) {
      whereParts.add('sm.movement_type = ?');
      baseVars.add(Variable.withString(movementType));
    }

    final where = whereParts.join(' AND ');

    final countRow = await _db.customSelect(
      'SELECT COUNT(*) AS cnt FROM stock_movements sm WHERE $where',
      variables: baseVars,
      readsFrom: {_db.stockMovements},
    ).getSingle();
    final totalCount = (countRow.data['cnt'] as num).toInt();

    final offset = page * pageSize;
    final dataRows = await _db.customSelect(
      'SELECT sm.id, sm.movement_type, sm.quantity_change, sm.stock_before, '
      'sm.stock_after, sm.reference_id, sm.reference_type, sm.note, '
      'sm.created_at, sm.created_by_user_id, u.full_name AS user_name '
      'FROM stock_movements sm '
      'LEFT JOIN users u ON u.id = sm.created_by_user_id '
      'WHERE $where '
      'ORDER BY sm.created_at DESC '
      'LIMIT ? OFFSET ?',
      variables: [
        ...baseVars,
        Variable.withInt(pageSize),
        Variable.withInt(offset),
      ],
      readsFrom: {_db.stockMovements, _db.usersTable},
    ).get();

    final rows = dataRows
        .map(
          (r) => StockMovementRow(
            id: r.data['id'] as int,
            createdAt: _parseDate(r.data['created_at']),
            movementType: r.data['movement_type'] as String,
            quantityChange: (r.data['quantity_change'] as num).toDouble(),
            stockBefore: (r.data['stock_before'] as num).toDouble(),
            stockAfter: (r.data['stock_after'] as num).toDouble(),
            referenceId: r.data['reference_id'] as int?,
            referenceType: r.data['reference_type'] as String?,
            note: r.data['note'] as String?,
            createdByUserId: r.data['created_by_user_id'] as int?,
            userName: r.data['user_name'] as String?,
          ),
        )
        .toList();

    return (rows: rows, totalCount: totalCount);
  }
}
