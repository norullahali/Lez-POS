// lib/features/pos/models/cart_item.dart
import 'dart:convert';
import '../../products/models/product_model.dart';

class CartItem {
  final ProductModel product;
  final double quantity;
  final double unitPrice;       // price after rule applied
  final double originalPrice;  // product.sellPrice before any rule
  final double discount;       // per-item line discount (absolute)
  final int? appliedRuleId;
  final String? appliedRuleLabel; // e.g. "خصم 10%", "سعر الجملة"
  final bool isFreeItem;       // true = BUY_X_GET_Y free unit (price=0)
  final bool isReturn;         // true = Item is being returned (negative value)

  const CartItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    double? originalPrice,
    this.discount = 0,
    this.appliedRuleId,
    this.appliedRuleLabel,
    this.isFreeItem = false,
    this.isReturn = false,
  }) : originalPrice = originalPrice ?? unitPrice;

  bool get hasDiscount => unitPrice < originalPrice || discount > 0;

  double get lineTotal => isFreeItem ? 0.0 : ((quantity * unitPrice) - discount) * (isReturn ? -1 : 1);
  double get effectiveQuantity => quantity * (isReturn ? -1 : 1);
  double get cost => (product.costPrice * quantity) * (isReturn ? -1 : 1);

  CartItem copyWith({
    double? quantity,
    double? unitPrice,
    double? originalPrice,
    double? discount,
    int? appliedRuleId,
    String? appliedRuleLabel,
    bool? isFreeItem,
    bool? isReturn,
  }) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      originalPrice: originalPrice ?? this.originalPrice,
      discount: discount ?? this.discount,
      appliedRuleId: appliedRuleId ?? this.appliedRuleId,
      appliedRuleLabel: appliedRuleLabel ?? this.appliedRuleLabel,
      isFreeItem: isFreeItem ?? this.isFreeItem,
      isReturn: isReturn ?? this.isReturn,
    );
  }

  // ── Serialization ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'product': {
          'id': product.id,
          'name': product.name,
          'barcode': product.barcode,
          'categoryId': product.categoryId,
          'categoryName': product.categoryName,
          'supplierId': product.supplierId,
          'supplierName': product.supplierName,
          'costPrice': product.costPrice,
          'sellPrice': product.sellPrice,
          'wholesalePrice': product.wholesalePrice,
          'unit': product.unit,
          'minStock': product.minStock,
          'trackExpiry': product.trackExpiry,
          'isActive': product.isActive,
          // currentStock intentionally omitted — always validated live from DB
        },
        'quantity': quantity,
        'unitPrice': unitPrice,
        'originalPrice': originalPrice,
        'discount': discount,
        'appliedRuleId': appliedRuleId,
        'appliedRuleLabel': appliedRuleLabel,
        'isFreeItem': isFreeItem,
        'isReturn': isReturn,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final p = json['product'] as Map<String, dynamic>;
    return CartItem(
      product: ProductModel(
        id: p['id'] as int?,
        name: p['name'] as String,
        barcode: (p['barcode'] as String?) ?? '',
        categoryId: p['categoryId'] as int?,
        categoryName: p['categoryName'] as String?,
        supplierId: p['supplierId'] as int?,
        supplierName: p['supplierName'] as String?,
        costPrice: (p['costPrice'] as num).toDouble(),
        sellPrice: (p['sellPrice'] as num).toDouble(),
        wholesalePrice: (p['wholesalePrice'] as num).toDouble(),
        unit: (p['unit'] as String?) ?? 'قطعة',
        minStock: (p['minStock'] as num).toDouble(),
        trackExpiry: (p['trackExpiry'] as bool?) ?? false,
        isActive: (p['isActive'] as bool?) ?? true,
        currentStock: 0, // live value — not persisted
      ),
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
      originalPrice: (json['originalPrice'] as num).toDouble(),
      discount: (json['discount'] as num).toDouble(),
      appliedRuleId: json['appliedRuleId'] as int?,
      appliedRuleLabel: json['appliedRuleLabel'] as String?,
      isFreeItem: (json['isFreeItem'] as bool?) ?? false,
      isReturn: (json['isReturn'] as bool?) ?? false,
    );
  }

  // Convenience helpers
  static String listToJsonString(List<CartItem> items) =>
      jsonEncode(items.map((i) => i.toJson()).toList());

  static List<CartItem> listFromJsonString(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}

class PaymentInfo {
  final String method; // CASH / CARD / MIXED / DEBT
  final double cashPaid;
  final double cardPaid;
  final double change;
  final double debtAmount; // portion charged on credit
  final double pointsUsed; // loyalty points redeemed
  final double loyaltyDiscount; // cash value of redeemed points

  const PaymentInfo({
    required this.method,
    this.cashPaid = 0,
    this.cardPaid = 0,
    this.change = 0,
    this.debtAmount = 0,
    this.pointsUsed = 0,
    this.loyaltyDiscount = 0,
  });
}

