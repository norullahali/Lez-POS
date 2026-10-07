// lib/core/database/daos/product_opening_stock_seals_dao.dart

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/product_opening_stock_seals_table.dart';

part 'product_opening_stock_seals_dao.g.dart';

@DriftAccessor(tables: [ProductOpeningStockSeals])
class ProductOpeningStockSealsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductOpeningStockSealsDaoMixin {
  ProductOpeningStockSealsDao(super.db);

  Future<ProductOpeningStockSeal?> findByProductId(int productId) =>
      (select(productOpeningStockSeals)
            ..where((r) => r.productId.equals(productId)))
          .getSingleOrNull();

  Future<void> insertSeal({
    required int productId,
    required double quantity,
    required double unitCost,
    required String idempotencyKey,
    required int createdBy,
  }) =>
      into(productOpeningStockSeals).insert(
        ProductOpeningStockSealsCompanion.insert(
          productId: Value(productId),
          quantity: quantity,
          unitCost: unitCost,
          idempotencyKey: idempotencyKey,
          createdBy: createdBy,
        ),
      );
}