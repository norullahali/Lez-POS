import 'package:flutter/foundation.dart';
// lib/core/services/opening_stock_service.dart
import '../database/app_database.dart';
import '../../features/opening_stock/repositories/opening_stock_repository.dart';
import '../../features/opening_stock/providers/opening_stock_provider.dart';

class OpeningStockService {
  final AppDatabase db;
  final OpeningStockRepository repository;

  OpeningStockService(this.db, this.repository);

  /// Saves multiple opening stock entries as a single atomic transaction.
  Future<void> saveBulkOpeningStock(List<OpeningStockEntry> entries) async {
    try {
      await db.transaction(() async {
        for (final entry in entries) {
          // Validation and orchestration logic belongs here
          await repository.saveOpeningStock(
            entry.productId,
            entry.quantity,
            entry.unitCost,
          );
        }

        // Record a cumulative audit log
        await db.logsDao.insertLog(
          userId: null, // TODO: Auth service integration
          actionType: 'OPENING_STOCK_SAVE',
          details: 'Saved opening stock for ${entries.length} products.',
        );
      });
    } catch (e, st) {
      debugPrint('[OpeningStockService] Error in saveBulkOpeningStock: $e\n$st');
      if (e is Exception) rethrow;
      throw Exception('فشل في حفظ الرصيد الافتتاحي: ${e.toString()}');
    }
  }
}
