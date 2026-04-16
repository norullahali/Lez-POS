// lib/features/pos/providers/pos_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/database/app_database.dart';
import '../models/cart_session.dart';
import '../models/cart_item.dart';
import '../repositories/pos_repository.dart';
import '../../products/models/product_model.dart';
import '../../pricing/services/pricing_engine.dart';
import '../../pricing/providers/pricing_provider.dart';
import '../../../core/services/pos_sale_service.dart';
import '../../../core/utils/invoice_generator.dart';
import '../../../core/utils/invoice_pdf_builder.dart';
import 'package:drift/drift.dart' show Value;
import 'package:printing/printing.dart';

final posRepositoryProvider = Provider<PosRepository>((ref) {
  return PosRepository(AppDatabase.instance);
});

final posSaleServiceProvider = Provider<PosSaleService>((ref) {
  return PosSaleService(AppDatabase.instance);
});

// ---- Session Provider ----
class PosSessionNotifier extends AsyncNotifier<PosSession?> {
  @override
  Future<PosSession?> build() {
    return ref.watch(posRepositoryProvider).getOpenSession();
  }

  Future<void> openSession(String cashierName, double openingCash) async {
    final userId = ref.read(authProvider).valueOrNull?.user?.id;
    await ref.read(posRepositoryProvider).openSession(cashierName, openingCash, userId);
    ref.invalidateSelf();
  }

  Future<Map<String, dynamic>> closeSession(double closingCash) async {
    final session = state.valueOrNull;
    if (session == null) return {};
    final summary = await ref.read(posRepositoryProvider).getSessionSummary(session.id);
    await ref.read(posRepositoryProvider).closeSession(session.id, closingCash);
    ref.invalidateSelf();
    return summary;
  }
}

final posSessionProvider =
    AsyncNotifierProvider<PosSessionNotifier, PosSession?>(PosSessionNotifier.new);

// ---- Cart State ----
class CartState {
  final Map<int, CartSession> carts;
  final int activeCartId;
  final bool restoredFromStorage;

  const CartState({
    required this.carts,
    required this.activeCartId,
    this.restoredFromStorage = false,
  });

  CartSession get activeCart => carts[activeCartId]!;
  List<CartItem> get activeCartItems => activeCart.items;

  // Convenience getters for UI compatibility
  List<CartItem> get items => activeCart.items;
  double get invoiceDiscount => activeCart.invoiceDiscount;
  int? get selectedIndex => activeCart.selectedIndex;
  Customer? get selectedCustomer => activeCart.selectedCustomer;
  double get subtotal => activeCart.subtotal;
  double get total => activeCart.total;
  // Loyalty convenience getters
  double get loyaltyPointsUsed => activeCart.loyaltyPointsUsed;
  double get loyaltyDiscount => activeCart.loyaltyDiscount;

  CartState copyWith({
    Map<int, CartSession>? carts,
    int? activeCartId,
    bool? restoredFromStorage,
  }) {
    return CartState(
      carts: carts ?? this.carts,
      activeCartId: activeCartId ?? this.activeCartId,
      restoredFromStorage: restoredFromStorage ?? this.restoredFromStorage,
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  static const _kStorageKey = 'pos_carts_v1';
  static const _kActiveIdKey = 'pos_active_cart_id_v1';

  PricingEngine get _engine => ref.read(pricingEngineProvider);

  @override
  CartState build() {
    final userId = ref.read(authProvider).valueOrNull?.user?.id;
    final firstCart = CartSession(
      id: 1,
      createdAt: DateTime.now(),
      createdByUserId: userId,
      lastModifiedByUserId: userId,
    );
    final defaultState = CartState(
      carts: {1: firstCart},
      activeCartId: 1,
    );
    // Kick off async restore — will update state when ready.
    // Errors are caught inside so this never throws.
    Future.microtask(() => _loadCartsFromStorage());
    return defaultState;
  }

  // ── Persistence ───────────────────────────────────────────────────────

  Future<void> _saveCartsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = CartSession.mapToJsonString(state.carts);
      await prefs.setString(_kStorageKey, json);
      await prefs.setInt(_kActiveIdKey, state.activeCartId);
    } catch (_) {
      // Never crash on save failure
    }
  }

  Future<void> _loadCartsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw == null || raw.isEmpty) return;

      final restored = CartSession.mapFromJsonString(raw);
      if (restored.isEmpty) return;

      // Ensure Cart 1 always exists
      if (!restored.containsKey(1)) {
        restored[1] = CartSession(id: 1, createdAt: DateTime.now());
      }

      final savedActiveId = prefs.getInt(_kActiveIdKey) ?? 1;
      final activeId = restored.containsKey(savedActiveId) ? savedActiveId : 1;

      // Check if any cart actually has items before marking as restored
      final hasItems = restored.values.any((c) => c.items.isNotEmpty);
      state = CartState(
        carts: restored,
        activeCartId: activeId,
        restoredFromStorage: hasItems,
      );
    } catch (_) {
      // Corrupted JSON — silently reset to default
    }
  }

  // ── Multi-Cart Management ──────────────────────────────────────────────────────

  void switchCart(int cartId) {
    if (state.carts.containsKey(cartId)) {
      state = state.copyWith(activeCartId: cartId);
      _saveCartsToStorage();
    }
  }

  void createCart() {
    if (state.carts.length >= 3) return;

    final userId = ref.read(authProvider).valueOrNull?.user?.id;

    // Find next available ID (2 or 3)
    int nextId = -1;
    for (int i = 1; i <= 3; i++) {
      if (!state.carts.containsKey(i)) {
        nextId = i;
        break;
      }
    }

    if (nextId != -1) {
      final newCart = CartSession(
        id: nextId,
        createdAt: DateTime.now(),
        createdByUserId: userId,
        lastModifiedByUserId: userId,
      );
      final newCarts = Map<int, CartSession>.from(state.carts);
      newCarts[nextId] = newCart;
      state = state.copyWith(carts: newCarts, activeCartId: nextId);
      _saveCartsToStorage();
    }
  }

  void removeCart(int cartId) {
    if (cartId == 1) return; // Cannot remove Cart 1
    if (!state.carts.containsKey(cartId)) return;

    final newCarts = Map<int, CartSession>.from(state.carts);
    newCarts.remove(cartId);

    int newActiveId = state.activeCartId;
    if (state.activeCartId == cartId) {
      newActiveId = 1;
    }

    state = state.copyWith(carts: newCarts, activeCartId: newActiveId);
    _saveCartsToStorage();
  }

  // ── Helper to update active cart ───────────────────────────────────────────
  void _updateActiveCart(CartSession updated) {
    final userId = ref.read(authProvider).valueOrNull?.user?.id;
    final finalUpdated = updated.copyWith(lastModifiedByUserId: userId);

    final newCarts = Map<int, CartSession>.from(state.carts);
    newCarts[state.activeCartId] = finalUpdated;
    state = state.copyWith(carts: newCarts);
  }

  // ── Apply pricing engine to a product + qty ──────────────────────────────
  CartItem _applyPricing(ProductModel product, double qty) {
    final ap = _engine.applyToItem(product, qty);
    return CartItem(
      product: product,
      quantity: qty,
      unitPrice: ap.unitPrice,
      originalPrice: product.sellPrice,
      discount: ap.discount,
      appliedRuleId: ap.ruleId,
      appliedRuleLabel: ap.label,
    );
  }

  // ── Re-evaluate all items (call when rules reload) ───────────────────────
  void applyPricingRules() {
    final items = state.items.map((item) {
      if (item.isFreeItem) return item; // preserve free items
      return _applyPricing(item.product, item.quantity);
    }).toList();
    _syncFreeItems(items);
  }

  // ── BUY_X_GET_Y free item sync ────────────────────────────────────────────
  void _syncFreeItems(List<CartItem> paidItems) {
    final lines = paidItems
        .where((i) => !i.isFreeItem)
        .map((i) => (
              productId: i.product.id ?? 0,
              categoryId: i.product.categoryId,
              quantity: i.quantity,
            ))
        .toList();

    final freeMap = _engine.computeFreeItems(cartLines: lines);

    // Remove old free items
    final withoutFree = paidItems.where((i) => !i.isFreeItem).toList();

    // Add new free items
    final allItems = [...withoutFree];
    for (final entry in freeMap.entries) {
      final productId = entry.key;
      final freeQty   = entry.value;
      // Find product model from existing paid items
      final base = paidItems.firstWhere(
        (i) => i.product.id == productId,
        orElse: () => paidItems.first,
      );
      allItems.add(CartItem(
        product: base.product,
        quantity: freeQty,
        unitPrice: 0,
        originalPrice: base.product.sellPrice,
        isFreeItem: true,
        appliedRuleLabel: 'مجاناً',
      ));
    }

    _updateActiveCart(state.activeCart.copyWith(
      items: allItems, 
      selectedIndex: state.selectedIndex,
    ));
  }

  // ── Public Cart API ───────────────────────────────────────────────────────

  void addProduct(ProductModel product, {double qty = 1}) {
    final active = state.activeCart;
    final existing = active.items.indexWhere(
      (i) => i.product.id == product.id && !i.isFreeItem,
    );
    List<CartItem> items;
    if (existing >= 0) {
      items = [...active.items];
      final newQty = items[existing].quantity + qty;
      items[existing] = _applyPricing(product, newQty);
      _updateActiveCart(active.copyWith(items: items, selectedIndex: existing));
    } else {
      final newItem = _applyPricing(product, qty);
      items = [...active.items, newItem];
      _updateActiveCart(active.copyWith(items: items, selectedIndex: items.length - 1));
    }
    _syncFreeItems(state.items);
    _saveCartsToStorage();
  }

  void setQuantity(int index, double qty) {
    if (qty <= 0) {
      removeItem(index);
      return;
    }
    final active = state.activeCart;
    final items = [...active.items];
    final item = items[index];
    if (!item.isFreeItem) {
      items[index] = _applyPricing(item.product, qty);
    }
    _updateActiveCart(active.copyWith(items: items));
    _syncFreeItems(state.items);
    _saveCartsToStorage();
  }

  void incrementQty(int index) {
    final active = state.activeCart;
    final items = [...active.items];
    final item  = items[index];
    if (!item.isFreeItem) {
      final newQty = item.quantity + 1;
      items[index] = _applyPricing(item.product, newQty);
    }
    _updateActiveCart(active.copyWith(items: items));
    _syncFreeItems(state.items);
  }

  void toggleReturnItem(int index) {
    final active = state.activeCart;
    final items = [...active.items];
    final item = items[index];
    if (item.isFreeItem) return; // Cannot return algorithmic free items directly
    
    items[index] = item.copyWith(isReturn: !item.isReturn);
    _updateActiveCart(active.copyWith(items: items));
    _saveCartsToStorage();
  }

  void decrementQty(int index) {
    final active = state.activeCart;
    final item = active.items[index];
    if (item.isFreeItem) return; // cannot manually change free items
    if (item.quantity <= 1) {
      removeItem(index);
    } else {
      final items = [...active.items];
      items[index] = _applyPricing(item.product, item.quantity - 1);
      _updateActiveCart(active.copyWith(items: items));
      _syncFreeItems(state.items);
    }
  }

  void setItemDiscount(int index, double discount) {
    final active = state.activeCart;
    final items = [...active.items];
    items[index] = items[index].copyWith(discount: discount);
    _updateActiveCart(active.copyWith(items: items));
  }

  void setItemPrice(int index, double price) {
    final active = state.activeCart;
    final items = [...active.items];
    items[index] = items[index].copyWith(unitPrice: price);
    _updateActiveCart(active.copyWith(items: items));
  }

  void setInvoiceDiscount(double discount) {
    final active = state.activeCart;
    _updateActiveCart(active.copyWith(invoiceDiscount: discount));
  }

  /// Apply loyalty points redemption to the active cart.
  /// [points] — number of points the customer wants to use.
  /// [discount] — the cash discount equivalent (computed by LoyaltyService).
  void setLoyaltyPoints(double points, double discount) {
    final active = state.activeCart;
    _updateActiveCart(active.copyWith(
      loyaltyPointsUsed: points,
      loyaltyDiscount: discount,
    ));
    _saveCartsToStorage();
  }

  /// Remove any loyalty discount from the active cart.
  void clearLoyaltyPoints() {
    final active = state.activeCart;
    _updateActiveCart(active.copyWith(
      loyaltyPointsUsed: 0,
      loyaltyDiscount: 0,
    ));
    _saveCartsToStorage();
  }

  void removeItem(int index) {
    final active = state.activeCart;
    final items = [...active.items]..removeAt(index);
    _updateActiveCart(active.copyWith(items: items, selectedIndex: null));
    _syncFreeItems(state.items);
    _saveCartsToStorage();
  }

  void selectItem(int index) {
    final active = state.activeCart;
    _updateActiveCart(active.copyWith(selectedIndex: index));
  }

  void selectCustomer(Customer? customer) {
    final active = state.activeCart;
    _updateActiveCart(active.copyWith(selectedCustomer: customer));
  }

  void clearCart() {
    final active = state.activeCart;
    _updateActiveCart(CartSession(
      id: active.id,
      createdAt: active.createdAt,
    ));
    _saveCartsToStorage();
  }

  // ── Checkout ─────────────────────────────────────────────────────────────
  Future<void> checkout({
    required int? sessionId,
    required String invoiceNumber,
    required PaymentInfo payment,
    required int? userId,
    int? approvedByUserId,
  }) async {
    final saleService = ref.read(posSaleServiceProvider);
    final active = state.activeCart;
    final authUser = ref.read(authProvider).valueOrNull?.user;

    final sale = SalesInvoicesCompanion(
      sessionId: Value(sessionId),
      invoiceNumber: Value(invoiceNumber),
      subtotal: Value(active.subtotal),
      discountAmount: Value(active.invoiceDiscount + active.loyaltyDiscount),
      total: Value(active.total),
      paymentMethod: Value(payment.method),
      cashPaid: Value(payment.cashPaid),
      cardPaid: Value(payment.cardPaid),
      changeAmount: Value(payment.change),
      debtAmount: Value(payment.debtAmount.clamp(0.0, active.total)),
      createdByUserId: Value(userId),
      processedByUserId: Value(userId),
      customerId: Value(active.selectedCustomer?.id),
    );

    final itemCompanions = active.items.map((item) => SaleItemsCompanion(
      productId: Value(item.product.id!),
      quantity: Value(item.effectiveQuantity),
      unitPrice: Value(item.unitPrice),
      unitCost: Value(item.product.costPrice),
      discountAmount: Value(item.discount),
      total: Value(item.lineTotal),
    )).toList();

    await saleService.processSale(
      invoice: sale,
      items: itemCompanions,
      debtAmount: payment.debtAmount,
      // Loyalty: pass the redeemed points and the net amount paid to earn from.
      pointsUsed: active.loyaltyPointsUsed,
      netSaleTotal: active.total,
      approvedByUserId: approvedByUserId,
    );

    final paidAmount = (active.total - payment.debtAmount).clamp(0.0, active.total);
    final remainingAmount = payment.debtAmount.clamp(0.0, active.total);
    final invoiceData = InvoiceGenerator().generateInvoiceData(
      invoiceNumber: invoiceNumber,
      date: DateTime.now(),
      cashierName: authUser?.fullName ?? authUser?.username ?? 'Unknown Cashier',
      items: active.items
          .map(
            (item) => <String, dynamic>{
              'name': item.product.name,
              'quantity': item.effectiveQuantity,
              'price': item.unitPrice,
              'total': item.lineTotal,
            },
          )
          .toList(),
      total: active.total,
      paid: paidAmount,
      remaining: remainingAmount,
      customerName: active.selectedCustomer?.name,
      loyaltyPoints:
          active.loyaltyPointsUsed > 0 ? active.loyaltyPointsUsed.round() : null,
    );
    print('INVOICE DATA: $invoiceData');

    /// Printing is non-blocking and should not affect sale success
    try {
      final invoiceItems = (invoiceData['items'] as List<dynamic>)
          .map(
            (item) => InvoiceItemData(
              name: item['name'] as String? ?? '',
              quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
              price: (item['price'] as num?)?.toDouble() ?? 0,
              total: (item['total'] as num?)?.toDouble() ?? 0,
            ),
          )
          .toList();

      final pdfInvoiceData = InvoiceData(
        invoiceNumber: invoiceData['invoiceNumber'] as String? ?? invoiceNumber,
        date: invoiceData['date'] as DateTime? ?? DateTime.now(),
        cashierName: invoiceData['cashierName'] as String? ?? '',
        items: invoiceItems,
        total: (invoiceData['total'] as num?)?.toDouble() ?? 0,
        paid: (invoiceData['paid'] as num?)?.toDouble() ?? 0,
        remaining: (invoiceData['remaining'] as num?)?.toDouble() ?? 0,
        customerName: invoiceData['customerName'] as String?,
        loyaltyPoints: invoiceData['loyaltyPoints'] as int?,
      );

      final pdfBytes = await InvoicePdfBuilder().build(pdfInvoiceData);
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
      );
    } catch (e) {
      print('PRINT ERROR: $e');
    }
  }
}


final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);

// ---- Invoice Number Generator ----
int _invoiceCounter = 1;
String generateInvoiceNumber() {
  final now = DateTime.now();
  final prefix = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  return '$prefix-${(_invoiceCounter++).toString().padLeft(4, '0')}';
}
