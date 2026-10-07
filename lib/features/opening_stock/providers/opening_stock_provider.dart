// lib/features/opening_stock/providers/opening_stock_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/opening_stock_save_fingerprint.dart';
import '../../../core/services/opening_stock_save_result.dart';
import '../../../core/services/opening_stock_save_service.dart';
import '../../../core/services/opening_stock_service.dart';
import '../repositories/opening_stock_repository.dart';
import 'opening_stock_save_service_provider.dart';

final openingStockRepositoryProvider = Provider<OpeningStockRepository>((ref) {
  return OpeningStockRepository(AppDatabase.instance);
});

final openingStockServiceProvider = Provider<OpeningStockService>((ref) {
  return OpeningStockService(
    AppDatabase.instance,
    ref.read(openingStockRepositoryProvider),
    ref.read(openingStockSaveServiceProvider),
  );
});

class OpeningStockEntry {
  final int productId;
  final String productName;
  final String productUnit;
  final double quantity;
  final double unitCost;

  const OpeningStockEntry({
    required this.productId,
    required this.productName,
    required this.productUnit,
    required this.quantity,
    this.unitCost = 0,
  });
}

class OpeningStockNotifier extends Notifier<List<OpeningStockEntry>> {
  @override
  List<OpeningStockEntry> build() => [];

  void addEntry(OpeningStockEntry entry) {
    final existing = state.indexWhere((e) => e.productId == entry.productId);
    if (existing >= 0) {
      final newState = [...state];
      newState[existing] = entry;
      state = newState;
    } else {
      state = [...state, entry];
    }
  }

  void removeEntry(int productId) {
    state = state.where((e) => e.productId != productId).toList();
  }

  void clear() => state = [];

  Future<OpeningStockSaveResult> save({
    required String idempotencyKey,
    required String fingerprintHash,
    required int createdBy,
  }) async {
    final service = ref.read(openingStockServiceProvider);
    final result = await service.saveBulkOpeningStock(
      idempotencyKey: idempotencyKey,
      fingerprintHash: fingerprintHash,
      entries: state,
      createdBy: createdBy,
    );
    state = [];
    return result;
  }

  String computeFingerprint(int createdBy) {
    return OpeningStockSaveFingerprint.compute(
      products: state
          .map(
            (entry) => OpeningStockFingerprintProduct(
              productId: entry.productId,
              quantity: entry.quantity,
              unitCost: entry.unitCost,
            ),
          )
          .toList(),
      createdBy: createdBy,
    );
  }
}

final openingStockNotifierProvider =
    NotifierProvider<OpeningStockNotifier, List<OpeningStockEntry>>(
  OpeningStockNotifier.new,
);
