// lib/features/pricing/services/pricing_engine.dart
//
// In-memory rule engine. Rules are loaded once from DB via [PricingProvider].
// All evaluation happens in Dart – ZERO database queries at search time.
//
// Design:
//   - Rules sorted by priority DESC at load time.
//   - applyToItem:  returns AppliedPrice for a given product + quantity.
//   - freeItemsFor: handles BUY_X_GET_Y logic across the whole cart.
//   - isActive:     time-based filter enforced at evaluation time.

import '../../../features/products/models/product_model.dart';
import '../models/pricing_rule_model.dart';

class PricingEngine {
  List<PricingRuleModel> _rules = [];
  // Future hook: synonyms / loyalty tier injected here
  // String? _activeCoupon;
  // int? _customerGroupId;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  /// Load (or reload) rules from the DB result. Already sorted by priority.
  void loadRules(List<PricingRuleModel> rules) {
    // Sort highest priority first; secondary sort: best discount
    _rules = List.of(rules)
      ..sort((a, b) {
        final cmp = b.priority.compareTo(a.priority);
        if (cmp != 0) return cmp;
        // Tiebreak: higher percentage / amount wins
        return b.discountPercentage.compareTo(a.discountPercentage);
      });
  }

  int get ruleCount => _rules.length;

  // ─────────────────────────────────────────────────────────────────────────
  // Item-level pricing
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the best [AppliedPrice] for a single [product] at [quantity].
  /// Will skip BUY_X_GET_Y rules (those are cart-level, handled separately).
  AppliedPrice applyToItem(ProductModel product, double quantity) {
    final now = DateTime.now();

    for (final rule in _rules) {
      // Skip time-invalid, inactive, or cart-level rules
      if (!_isDateValid(rule, now)) continue;
      if (rule.ruleType == RuleType.buyXGetY) continue;

      // Check conditions
      if (!_matchesProduct(rule, product)) continue;
      if (quantity < rule.minimumQuantity) continue;

      return _computePrice(rule, product, quantity);
    }

    return AppliedPrice.none(product.sellPrice);
  }

  /// Re-applies pricing to a list of [prices] produced by [applyToItem].
  /// Stateless – safe to call when quantity changes.
  AppliedPrice reapply(ProductModel product, double quantity) =>
      applyToItem(product, quantity);

  // ─────────────────────────────────────────────────────────────────────────
  // Cart-level: BUY_X_GET_Y
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns a list of (productId → freeQuantity) for BUY_X_GET_Y rules.
  /// The caller (CartNotifier) inserts zero-price items into the cart.
  Map<int, double> computeFreeItems({
    required List<({int productId, int? categoryId, double quantity})> cartLines,
  }) {
    final now = DateTime.now();
    final freeMap = <int, double>{};

    for (final rule in _rules) {
      if (rule.ruleType != RuleType.buyXGetY) continue;
      if (!_isDateValid(rule, now)) continue;

      for (final line in cartLines) {
        // Match scope
        final matchProd  = rule.productId == null || rule.productId == line.productId;
        final matchCat   = rule.categoryId == null || rule.categoryId == line.categoryId;
        if (!matchProd || !matchCat) continue;

        if (line.quantity < rule.buyQuantity) continue;

        // How many full "buy X" groups?
        final groups = (line.quantity / rule.buyQuantity).floor();
        final free   = groups * rule.getQuantity;
        if (free > 0) {
          freeMap[line.productId] = (freeMap[line.productId] ?? 0) + free;
        }
      }
    }

    return freeMap;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  bool _isDateValid(PricingRuleModel rule, DateTime now) {
    if (rule.startDate != null && now.isBefore(rule.startDate!)) return false;
    if (rule.endDate   != null && now.isAfter(rule.endDate!))   return false;
    return true;
  }

  bool _matchesProduct(PricingRuleModel rule, ProductModel product) {
    if (rule.productId != null  && rule.productId != product.id) return false;
    if (rule.categoryId != null && rule.categoryId != product.categoryId) return false;
    return true;
  }

  AppliedPrice _computePrice(
    PricingRuleModel rule,
    ProductModel product,
    double quantity,
  ) {
    final base = product.sellPrice;

    switch (rule.ruleType) {
      case RuleType.discountPercentage:
        final discUnit = base * rule.discountPercentage / 100;
        return AppliedPrice(
          unitPrice: base - discUnit,
          discount: discUnit * quantity,
          label: 'خصم ${rule.discountPercentage.toStringAsFixed(0)}%',
          ruleId: rule.id,
        );

      case RuleType.discountFixed:
        final discUnit = rule.discountAmount.clamp(0, base);
        return AppliedPrice(
          unitPrice: base - discUnit,
          discount: discUnit * quantity,
          label: 'خصم ${rule.discountAmount.toStringAsFixed(0)} د.ع',
          ruleId: rule.id,
        );

      case RuleType.wholesalePrice:
        final price = product.wholesalePrice;
        return AppliedPrice(
          unitPrice: price,
          discount: (base - price) * quantity,
          label: 'سعر الجملة',
          ruleId: rule.id,
        );

      case RuleType.specialPrice:
        final price = (rule.specialPrice ?? base).clamp(0.0, double.infinity);
        return AppliedPrice(
          unitPrice: price,
          discount: (base - price) * quantity,
          label: rule.name,
          ruleId: rule.id,
        );

      case RuleType.buyXGetY:
        // Handled at cart level
        return AppliedPrice.none(base);
    }
  }
}
