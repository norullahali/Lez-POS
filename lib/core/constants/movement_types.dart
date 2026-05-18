// lib/core/constants/movement_types.dart

/// Business-level kinds used in the [stock_movements] table.
///
/// These are intentionally distinct from the low-level [StockMovementType]
/// codes used in [stock_ledger] — one is accounting-grain, the other is
/// business-operation-grain.
class StockMovementKind {
  StockMovementKind._();

  static const String sale             = 'sale';
  static const String purchase         = 'purchase';
  static const String fullReturn       = 'full_return';
  static const String openingStock     = 'opening_stock';
  static const String manualAdjustment = 'manual_adjustment';

  static const List<String> all = [
    sale,
    purchase,
    fullReturn,
    openingStock,
    manualAdjustment,
  ];

  static String labelAr(String kind) {
    return switch (kind) {
      sale             => 'بيع',
      purchase         => 'شراء',
      fullReturn       => 'إرجاع كامل',
      openingStock     => 'رصيد افتتاحي',
      manualAdjustment => 'تسوية يدوية',
      _                => kind,
    };
  }
}

enum StockMovementType {
  opening('OPENING', 'رصيد افتتاحي'),
  purchase('PURCHASE', 'شراء'),
  sale('SALE', 'بيع'),
  returnIn('RETURN_IN', 'مرتجع من عميل'),
  returnOut('RETURN_OUT', 'مرتجع إلى مورد'),
  adjustment('ADJUSTMENT', 'تسوية مخزن'),
  damage('DAMAGE', 'تالف/هالك'),
  loss('LOSS', 'فقدان');

  const StockMovementType(this.code, this.label);
  final String code;
  final String label;

  static StockMovementType fromCode(String code) {
    return StockMovementType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StockMovementType.adjustment,
    );
  }
}

enum PaymentMethod {
  cash('CASH', 'نقدي'),
  card('CARD', 'بطاقة'),
  mixed('MIXED', 'مختلط');

  const PaymentMethod(this.code, this.label);
  final String code;
  final String label;

  static PaymentMethod fromCode(String code) {
    return PaymentMethod.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PaymentMethod.cash,
    );
  }
}

enum PurchaseStatus {
  draft('DRAFT', 'مسودة'),
  confirmed('CONFIRMED', 'مؤكد'),
  cancelled('CANCELLED', 'ملغي');

  const PurchaseStatus(this.code, this.label);
  final String code;
  final String label;

  static PurchaseStatus fromCode(String code) {
    return PurchaseStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PurchaseStatus.draft,
    );
  }
}
