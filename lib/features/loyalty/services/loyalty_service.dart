// lib/features/loyalty/services/loyalty_service.dart
//
// Isolated loyalty service.
// Reads live configuration from [SettingsService] instead of compile-time constants.
// Falls back to [LoyaltySettings.defaults] when the DB is unavailable.
//
// NOTE: Uses raw SQL for loyalty_points column until build_runner regenerates
// the typed Drift accessors. Run:
//   flutter pub run build_runner build --delete-conflicting-outputs

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/settings_service.dart';

/// Handles point computation and persistence for the loyalty system.
///
/// Rules enforced here:
///   - Walk-in customer (id == 1) is always excluded.
///   - Earned/redeemable amounts are driven by live [SettingsService] values,
///     so changing them in the settings screen takes effect on the next sale.
///   - Points are stored on `customers.loyalty_points` via raw SQL.
class LoyaltyService {
  final AppDatabase _db;
  final SettingsService _settings;

  LoyaltyService(this._db, this._settings);

  // ── Settings snapshot ─────────────────────────────────────────────────────

  /// Load live settings.  Cached per-call-site via Riverpod [loyaltySettingsProvider].
  Future<LoyaltySettings> _cfg() => _settings.loadLoyaltySettings();

  // ── Computation (uses live settings) ──────────────────────────────────────

  /// Points earned for spending [totalAmount] currency.
  /// Returns 0 if loyalty is disabled.
  Future<double> earnPoints(double totalAmount) async {
    final cfg = await _cfg();
    return cfg.earnedPoints(totalAmount);
  }

  /// Cash discount value of [points] loyalty points.
  Future<double> redeemPoints(double points) async {
    final cfg = await _cfg();
    return cfg.redemptionDiscount(points);
  }

  /// Maximum redeemable points for an invoice of [invoiceTotal].
  Future<double> maxRedeemable(double availablePoints, double invoiceTotal) async {
    final cfg = await _cfg();
    return cfg.maxRedeemable(availablePoints, invoiceTotal);
  }

  /// Whether the loyalty system is currently enabled.
  Future<bool> isEnabled() => _settings.isLoyaltyEnabled();

  // ── Validation ────────────────────────────────────────────────────────────

  /// Validates that [pointsToUse] ≤ [available] and ≤ max allowed by [total].
  /// Returns an Arabic error string, or null when the input is valid.
  Future<String?> validateRedemption({
    required double pointsToUse,
    required double available,
    required double invoiceTotal,
  }) async {
    if (pointsToUse <= 0) return null;
    final cfg = await _cfg();
    if (!cfg.enabled) return 'نظام النقاط غير مفعّل حالياً';
    if (pointsToUse > available) return 'النقاط المطلوبة تتجاوز رصيدك المتاح';
    final maxPts = cfg.maxRedeemable(available, invoiceTotal);
    if (pointsToUse > maxPts) {
      return 'النقاط المستخدمة لا يمكن أن تتجاوز قيمة الفاتورة';
    }
    return null;
  }

  // ── Persistence (raw SQL) ─────────────────────────────────────────────────

  /// Fetch the current loyalty-point balance of [customerId].
  Future<double> getPoints(int customerId) async {
    if (customerId == 1) return 0;
    final rows = await _db.customSelect(
      'SELECT loyalty_points FROM customers WHERE id = ?',
      variables: [Variable.withInt(customerId)],
      readsFrom: {_db.customers},
    ).get();
    if (rows.isEmpty) return 0;
    return (rows.first.data['loyalty_points'] as num?)?.toDouble() ?? 0;
  }

  /// Apply post-sale point changes (earn + deduct) inside the sale transaction.
  Future<void> applyPostSalePoints({
    required int customerId,
    required double earnedPoints,
    required double usedPoints,
  }) async {
    if (customerId == 1) return;
    final net = earnedPoints - usedPoints;
    if (net == 0) return;

    await _db.customStatement(
      'UPDATE customers SET loyalty_points = MAX(0, loyalty_points + ?) WHERE id = ?',
      [net, customerId],
    );

    debugPrint('[LoyaltyService] customer=$customerId earned=$earnedPoints '
        'used=$usedPoints net=$net');
  }

  /// Admin override — directly set a customer's points balance.
  Future<void> setPoints(int customerId, double points) async {
    if (customerId == 1) return;
    await _db.customStatement(
      'UPDATE customers SET loyalty_points = ? WHERE id = ?',
      [points.clamp(0, double.infinity), customerId],
    );
  }
}
