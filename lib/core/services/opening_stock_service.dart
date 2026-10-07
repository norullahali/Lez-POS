import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../../features/opening_stock/providers/opening_stock_provider.dart';
import '../../features/opening_stock/repositories/opening_stock_repository.dart';
import 'opening_stock_save_fingerprint.dart';
import 'opening_stock_save_result.dart';
import 'opening_stock_save_service.dart';

/// Legacy facade — delegates bulk save to [OpeningStockSaveService].
class OpeningStockService {
  OpeningStockService(this.db, this.repository, this.saveService);

  final AppDatabase db;
  final OpeningStockRepository repository;
  final OpeningStockSaveService saveService;

  Future<OpeningStockSaveResult> saveBulkOpeningStock({
    required String idempotencyKey,
    required String fingerprintHash,
    required List<OpeningStockEntry> entries,
    required int createdBy,
  }) {
    final products = entries
        .map(
          (entry) => OpeningStockFingerprintProduct(
            productId: entry.productId,
            quantity: entry.quantity,
            unitCost: entry.unitCost,
          ),
        )
        .toList();

    return saveService.processSave(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      products: products,
      createdBy: createdBy,
    );
  }
}
