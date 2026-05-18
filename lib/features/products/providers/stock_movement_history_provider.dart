// lib/features/products/providers/stock_movement_history_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../models/stock_movement_row.dart';
import '../repositories/stock_movement_history_repository.dart';

// ---------------------------------------------------------------------------
// Repository provider
// ---------------------------------------------------------------------------

final stockMovementHistoryRepositoryProvider =
    Provider<StockMovementHistoryRepository>((ref) {
  return StockMovementHistoryRepository(AppDatabase.instance);
});

// ---------------------------------------------------------------------------
// Query model
// ---------------------------------------------------------------------------

@immutable
class StockMovementQuery {
  final int productId;
  final int page;
  final int pageSize;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? movementType;

  const StockMovementQuery({
    required this.productId,
    this.page = 0,
    this.pageSize = 25,
    this.dateFrom,
    this.dateTo,
    this.movementType,
  });

  StockMovementQuery copyWith({
    int? page,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearDateFrom = false,
    bool clearDateTo = false,
    String? movementType,
    bool clearMovementType = false,
  }) {
    return StockMovementQuery(
      productId: productId,
      page: page ?? this.page,
      pageSize: pageSize,
      dateFrom: clearDateFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDateTo ? null : (dateTo ?? this.dateTo),
      movementType:
          clearMovementType ? null : (movementType ?? this.movementType),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockMovementQuery &&
          runtimeType == other.runtimeType &&
          productId == other.productId &&
          page == other.page &&
          pageSize == other.pageSize &&
          dateFrom == other.dateFrom &&
          dateTo == other.dateTo &&
          movementType == other.movementType;

  @override
  int get hashCode => Object.hash(
        productId,
        page,
        pageSize,
        dateFrom,
        dateTo,
        movementType,
      );
}

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

@immutable
class StockMovementPage {
  final List<StockMovementRow> rows;
  final int totalCount;
  final int page;
  final int pageSize;

  const StockMovementPage({
    required this.rows,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  bool get hasNextPage => (page + 1) * pageSize < totalCount;
  bool get hasPrevPage => page > 0;
  int get totalPages => (totalCount / pageSize).ceil();
}

// ---------------------------------------------------------------------------
// FutureProvider
// ---------------------------------------------------------------------------

final stockMovementHistoryProvider = FutureProvider.autoDispose
    .family<StockMovementPage, StockMovementQuery>((ref, query) async {
  final repo = ref.watch(stockMovementHistoryRepositoryProvider);
  final result = await repo.getPagedMovements(
    productId: query.productId,
    page: query.page,
    pageSize: query.pageSize,
    dateFrom: query.dateFrom,
    dateTo: query.dateTo,
    movementType: query.movementType,
  );
  return StockMovementPage(
    rows: result.rows,
    totalCount: result.totalCount,
    page: query.page,
    pageSize: query.pageSize,
  );
});
