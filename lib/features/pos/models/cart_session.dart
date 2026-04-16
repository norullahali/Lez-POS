// lib/features/pos/models/cart_session.dart
import 'dart:convert';
import 'cart_item.dart';
import '../../../core/database/app_database.dart';

class CartSession {
  final int id;
  final List<CartItem> items;
  final String? note;
  final DateTime createdAt;
  final double invoiceDiscount;
  final int? selectedIndex;
  final Customer? selectedCustomer;
  /// Loyalty points the customer chose to redeem in this session.
  final double loyaltyPointsUsed;
  /// Cash discount equivalent of the redeemed loyalty points.
  final double loyaltyDiscount;
  
  final int? createdByUserId;
  final int? lastModifiedByUserId;

  CartSession({
    required this.id,
    this.items = const [],
    this.note,
    required this.createdAt,
    this.invoiceDiscount = 0,
    this.selectedIndex,
    this.selectedCustomer,
    this.loyaltyPointsUsed = 0,
    this.loyaltyDiscount = 0,
    this.createdByUserId,
    this.lastModifiedByUserId,
  });

  double get subtotal => items.fold(0.0, (s, i) => s + i.lineTotal);
  double get total => subtotal - invoiceDiscount - loyaltyDiscount;

  CartSession copyWith({
    int? id,
    List<CartItem>? items,
    String? note,
    DateTime? createdAt,
    double? invoiceDiscount,
    int? selectedIndex,
    Customer? selectedCustomer,
    double? loyaltyPointsUsed,
    double? loyaltyDiscount,
    int? createdByUserId,
    int? lastModifiedByUserId,
  }) {
    return CartSession(
      id: id ?? this.id,
      items: items ?? this.items,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      invoiceDiscount: invoiceDiscount ?? this.invoiceDiscount,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      selectedCustomer: selectedCustomer ?? this.selectedCustomer,
      loyaltyPointsUsed: loyaltyPointsUsed ?? this.loyaltyPointsUsed,
      loyaltyDiscount: loyaltyDiscount ?? this.loyaltyDiscount,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      lastModifiedByUserId: lastModifiedByUserId ?? this.lastModifiedByUserId,
    );
  }

  // ── Serialization ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'items': items.map((i) => i.toJson()).toList(),
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'invoiceDiscount': invoiceDiscount,
        'loyaltyPointsUsed': loyaltyPointsUsed,
        'loyaltyDiscount': loyaltyDiscount,
        'createdByUserId': createdByUserId,
        'lastModifiedByUserId': lastModifiedByUserId,
        // selectedIndex is UI-only, not persisted
        'selectedCustomer': selectedCustomer == null
            ? null
            : {
                'id': selectedCustomer!.id,
                'name': selectedCustomer!.name,
              },
      };

  factory CartSession.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final rawCustomer = json['selectedCustomer'] as Map<String, dynamic>?;

    return CartSession(
      id: json['id'] as int,
      items: rawItems
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      invoiceDiscount: (json['invoiceDiscount'] as num?)?.toDouble() ?? 0,
      loyaltyPointsUsed: (json['loyaltyPointsUsed'] as num?)?.toDouble() ?? 0,
      loyaltyDiscount: (json['loyaltyDiscount'] as num?)?.toDouble() ?? 0,
      selectedIndex: null, // UI-only, reset on restore
      selectedCustomer: rawCustomer == null ? null : _customerFromJson(rawCustomer),
      createdByUserId: json['createdByUserId'] as int?,
      lastModifiedByUserId: json['lastModifiedByUserId'] as int?,
    );
  }

  static Customer? _customerFromJson(Map<String, dynamic> json) {
    // We only need id + name for UI display, so we reconstruct a minimal Customer.
    // Any real balance/debt data is always fetched live from the DB.
    return Customer(
      id: json['id'] as int,
      name: json['name'] as String,
      isActive: true,
      createdAt: DateTime.now(),
      creditLimit: 0,
      loyaltyPoints: 0,
    );
  }

  static String mapToJsonString(Map<int, CartSession> carts) =>
      jsonEncode(carts.values.map((c) => c.toJson()).toList());

  static Map<int, CartSession> mapFromJsonString(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    final sessions = list
        .map((e) => CartSession.fromJson(e as Map<String, dynamic>))
        .toList();
    return {for (final s in sessions) s.id: s};
  }
}
