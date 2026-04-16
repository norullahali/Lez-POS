// lib/features/pricing/models/pricing_rule_model.dart

/// Rule type — stored as TEXT string in SQLite.
enum RuleType {
  discountPercentage,
  discountFixed,
  buyXGetY,
  wholesalePrice,
  specialPrice;

  String get dbValue => switch (this) {
        RuleType.discountPercentage => 'DISCOUNT_PERCENTAGE',
        RuleType.discountFixed      => 'DISCOUNT_FIXED',
        RuleType.buyXGetY          => 'BUY_X_GET_Y',
        RuleType.wholesalePrice    => 'WHOLESALE_PRICE',
        RuleType.specialPrice      => 'SPECIAL_PRICE',
      };

  String get displayName => switch (this) {
        RuleType.discountPercentage => 'خصم بالنسبة المئوية',
        RuleType.discountFixed      => 'خصم بمبلغ ثابت',
        RuleType.buyXGetY          => 'اشترِ X خذ Y',
        RuleType.wholesalePrice    => 'سعر الجملة',
        RuleType.specialPrice      => 'سعر خاص',
      };

  static RuleType fromDb(String? s) => switch (s) {
        'DISCOUNT_PERCENTAGE' => RuleType.discountPercentage,
        'DISCOUNT_FIXED'      => RuleType.discountFixed,
        'BUY_X_GET_Y'         => RuleType.buyXGetY,
        'WHOLESALE_PRICE'     => RuleType.wholesalePrice,
        'SPECIAL_PRICE'       => RuleType.specialPrice,
        _                     => RuleType.discountPercentage,
      };
}

/// The result that the pricing engine returns for a single item.
class AppliedPrice {
  final double unitPrice;       // final unit price after rule
  final double discount;        // per-item total discount amount
  final String? label;          // e.g. "خصم 10%", "اشترِ 2 خذ 1"
  final int? ruleId;
  final bool isFreeItem;        // true when this item is a BUY_X_GET_Y gift

  const AppliedPrice({
    required this.unitPrice,
    this.discount = 0,
    this.label,
    this.ruleId,
    this.isFreeItem = false,
  });

  /// No rule applied – use product's own price.
  factory AppliedPrice.none(double sellPrice) =>
      AppliedPrice(unitPrice: sellPrice);
}

/// Full pricing rule model parsed from the joined DB rows.
class PricingRuleModel {
  final int id;
  final String name;
  final RuleType ruleType;
  final int priority;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final DateTime createdAt;
  // Future-ready fields
  final int? customerGroupId;
  final String? couponCode;

  // Condition
  final int? productId;
  final int? categoryId;
  final double minimumQuantity;
  final double minimumTotalPrice;

  // Action
  final double discountPercentage;
  final double discountAmount;
  final double? specialPrice;
  final int buyQuantity;
  final int getQuantity;

  const PricingRuleModel({
    required this.id,
    required this.name,
    required this.ruleType,
    required this.priority,
    this.startDate,
    this.endDate,
    required this.isActive,
    required this.createdAt,
    this.customerGroupId,
    this.couponCode,
    this.productId,
    this.categoryId,
    this.minimumQuantity = 0,
    this.minimumTotalPrice = 0,
    this.discountPercentage = 0,
    this.discountAmount = 0,
    this.specialPrice,
    this.buyQuantity = 1,
    this.getQuantity = 0,
  });

  /// Parses a raw SQL Map row (from the joined query).
  factory PricingRuleModel.fromMap(Map<String, dynamic> m) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      return null;
    }

    return PricingRuleModel(
      id: m['id'] as int,
      name: m['name'] as String? ?? '',
      ruleType: RuleType.fromDb(m['rule_type'] as String?),
      priority: m['priority'] as int? ?? 0,
      startDate: parseDt(m['start_date']),
      endDate: parseDt(m['end_date']),
      isActive: (m['is_active'] as int? ?? 1) == 1,
      createdAt: parseDt(m['created_at']) ?? DateTime.now(),
      customerGroupId: m['customer_group_id'] as int?,
      couponCode: m['coupon_code'] as String?,
      productId: m['product_id'] as int?,
      categoryId: m['category_id'] as int?,
      minimumQuantity: (m['minimum_quantity'] as num?)?.toDouble() ?? 0,
      minimumTotalPrice: (m['minimum_total_price'] as num?)?.toDouble() ?? 0,
      discountPercentage: (m['discount_percentage'] as num?)?.toDouble() ?? 0,
      discountAmount: (m['discount_amount'] as num?)?.toDouble() ?? 0,
      specialPrice: (m['special_price'] as num?)?.toDouble(),
      buyQuantity: m['buy_quantity'] as int? ?? 1,
      getQuantity: m['get_quantity'] as int? ?? 0,
    );
  }
}
