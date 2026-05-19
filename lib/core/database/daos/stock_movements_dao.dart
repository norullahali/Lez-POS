// lib/core/database/daos/stock_movements_dao.dart
//
// Centralized DAO for recording high-level stock movements.
//
// Every inventory-changing operation (sale, purchase, full return,
// opening stock, manual adjustment) calls [recordMovement] INSIDE
// the same Drift transaction as the stock update, so if either
// operation fails the whole transaction rolls back atomically.

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/stock_movements_table.dart';

part 'stock_movements_dao.g.dart';

@DriftAccessor(tables: [StockMovements])
class StockMovementsDao extends DatabaseAccessor<AppDatabase>
    with _$StockMovementsDaoMixin {
  StockMovementsDao(super.db);

  // -- Core write -------------------------------------------------------------

  /// Inserts a single stock movement record.
  ///
  /// Must be called INSIDE the same database transaction as the corresponding
  /// stock update so that both operations either succeed or roll back together.
  ///
  /// [productId]       — product that changed.
  /// [movementType]    — one of [StockMovementKind] constants.
  /// [quantityChange]  — signed: positive = increase, negative = decrease.
  /// [stockBefore]     — [products.current_stock] BEFORE the update.
  /// [stockAfter]      — [products.current_stock] AFTER the update.
  /// [referenceId]     — PK of the source document (invoice, adjustment, ...).
  /// [referenceType]   — logical document type string for [referenceId].
  /// [note]            — optional free-text.
  /// [createdByUserId] — user who triggered the operation; null for system ops.
  Future<int> recordMovement({
    required int productId,
    required String movementType,
    required double quantityChange,
    required double stockBefore,
    required double stockAfter,
    int? referenceId,
    String? referenceType,
    String? note,
    int? createdByUserId,
  }) {
    return into(stockMovements).insert(
      StockMovementsCompanion.insert(
        productId: productId,
        movementType: movementType,
        quantityChange: quantityChange,
        stockBefore: stockBefore,
        stockAfter: stockAfter,
        referenceId: Value(referenceId),
        referenceType: Value(referenceType),
        note: Value(note),
        createdByUserId: Value(createdByUserId),
      ),
    );
  }

  // -- Reads (for future reports / screens) ----------------------------------

  /// All movements for a single product, newest first.
  Future<List<StockMovement>> getMovementsForProduct(int productId) =>
      (select(stockMovements)
            ..where((m) => m.productId.equals(productId))
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
          .get();

  /// Movements filtered by kind, newest first, with an optional limit.
  Future<List<StockMovement>> getMovementsByKind(
    String kind, {
    int limit = 100,
  }) =>
      (select(stockMovements)
            ..where((m) => m.movementType.equals(kind))
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
            ..limit(limit))
          .get();

  /// Most recent movements across all products.
  Future<List<StockMovement>> getRecentMovements({int limit = 50}) =>
      (select(stockMovements)
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
            ..limit(limit))
          .get();

  /// All movements within a date range.
  Future<List<StockMovement>> getMovementsInRange(
    DateTime from,
    DateTime to,
  ) =>
      (select(stockMovements)
            ..where(
              (m) => m.createdAt.isBetweenValues(from, to),
            )
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
          .get();
}
