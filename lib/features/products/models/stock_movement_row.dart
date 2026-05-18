// lib/features/products/models/stock_movement_row.dart
import 'package:flutter/foundation.dart';

@immutable
class StockMovementRow {
  final int id;
  final DateTime createdAt;
  final String movementType;
  final double quantityChange;
  final double stockBefore;
  final double stockAfter;
  final int? referenceId;
  final String? referenceType;
  final String? note;
  final int? createdByUserId;
  final String? userName;

  const StockMovementRow({
    required this.id,
    required this.createdAt,
    required this.movementType,
    required this.quantityChange,
    required this.stockBefore,
    required this.stockAfter,
    this.referenceId,
    this.referenceType,
    this.note,
    this.createdByUserId,
    this.userName,
  });
}
