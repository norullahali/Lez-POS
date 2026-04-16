// lib/core/constants/movement_types.dart

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
