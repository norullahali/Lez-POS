// lib/features/opening_stock/repositories/opening_stock_repository.dart
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class OpeningStockRepository {
  final AppDatabase _db;
  OpeningStockRepository(this._db);

  /// Advisory helper only — not an authoritative concurrency guard.
  Future<bool> hasOpeningEntry(int productId) async {
    final result = await _db.customSelect(
      "SELECT COUNT(*) as cnt FROM stock_ledger WHERE product_id = ? AND movement_type = 'OPENING'",
      variables: [Variable.withInt(productId)],
      readsFrom: {_db.stockLedger},
    ).getSingleOrNull();
    return ((result?.data['cnt'] as int?) ?? 0) > 0;
  }
}
