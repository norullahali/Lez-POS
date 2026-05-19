// lib/features/returns/models/smart_return_result.dart
import 'package:flutter/foundation.dart';

@immutable
class SmartReturnResult {
  final int invoiceId;
  final String invoiceNumber;
  final DateTime saleDate;
  final String customerName;
  final String cashierName;
  final String invoiceStatus;
  // Item-level fields
  final int saleItemId;
  final int productId;
  final String productName;
  final String barcode;
  final double soldQuantity;
  final double alreadyReturned;
  final double unitPrice;

  const SmartReturnResult({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.saleDate,
    required this.customerName,
    required this.cashierName,
    required this.invoiceStatus,
    required this.saleItemId,
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.soldQuantity,
    required this.alreadyReturned,
    required this.unitPrice,
  });

  double get remainingReturnable => (soldQuantity - alreadyReturned).clamp(0.0, double.infinity);

  bool get isFullyReturned => remainingReturnable <= 0;
}