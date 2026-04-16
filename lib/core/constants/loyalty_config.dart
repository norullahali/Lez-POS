// lib/core/constants/loyalty_config.dart
//
// Central configuration for the customer loyalty / reward-points system.
// All business rules live here — change a single value to tune the whole system.

/// Static loyalty configuration.
///
/// Earning:  [pointsPerCurrency] points are earned per 1 unit of currency paid.
///           Example: 0.1 → the customer earns 1 point for every 10 د.ع spent.
///
/// Redeeming: [redemptionValue] is the monetary worth of 1 loyalty point.
///            Example: 0.05 → 1 point = 0.05 د.ع discount.
///
/// Minimum:  [minRedeemPoints] is the lowest number of points that can be spent
///           in a single transaction (prevents micro-redemptions).
class LoyaltyConfig {
  LoyaltyConfig._();

  /// Points earned per 1 currency unit spent.
  /// 0.1  → 1 point per 10 د.ع
  static const double pointsPerCurrency = 0.1;

  /// Monetary value of 1 loyalty point when redeemed.
  /// 0.05 → 1 point = 0.05 د.ع
  static const double redemptionValue = 0.05;

  /// Minimum points that must be used in a single redemption.
  static const double minRedeemPoints = 10;

  // ── Derived helpers ──────────────────────────────────────────────────────

  /// How many points a customer earns for [amount] currency spent.
  static double earnedPoints(double amount) =>
      (amount * pointsPerCurrency).floorToDouble();

  /// Cash discount that [points] are worth.
  static double redemptionDiscount(double points) => points * redemptionValue;

  /// Maximum points that can be redeemed for a given [invoiceTotal]
  /// (the discount cannot exceed the invoice total).
  static double maxRedeemable(double availablePoints, double invoiceTotal) {
    final maxByTotal = (invoiceTotal / redemptionValue).floorToDouble();
    return availablePoints < maxByTotal ? availablePoints : maxByTotal;
  }
}
