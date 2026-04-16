// lib/core/services/settings_service.dart
//
// Typed service layer over AppSettingsDao.
// Provides strongly-typed get/set for every known application setting key,
// with safe fallbacks to compile-time defaults when a value is missing from DB.
//
// All methods use raw SQL via `customSelect`/`customStatement` so the service
// works correctly whether or not `build_runner` has been executed on the new
// AppSettings table. Once code-gen is run, nothing here needs to change.

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import '../constants/loyalty_config.dart';
import '../database/app_database.dart';

// ── Setting key constants ─────────────────────────────────────────────────────

abstract class SettingsKeys {
  static const String loyaltyEnabled     = 'loyalty_enabled';
  static const String pointsPerCurrency  = 'points_per_currency';
  static const String redemptionValue    = 'redemption_value';
  static const String storeName          = 'store_name';
  static const String storeLogoPath      = 'store_logo_path';
  static const String phone              = 'phone';
  static const String address            = 'address';
}

// ── Service ───────────────────────────────────────────────────────────────────

/// Typed settings service.  All reads fall back to safe compile-time defaults.
class SettingsService {
  final AppDatabase _db;
  SettingsService(this._db);

  // ── Low-level helpers (raw SQL — no .g.dart dependency) ──────────────────

  Future<String?> _getRaw(String key) async {
    try {
      final rows = await _db.customSelect(
        'SELECT value FROM app_settings WHERE key = ?',
        variables: [Variable.withString(key)],
      ).get();
      if (rows.isEmpty) return null;
      return rows.first.data['value'] as String?;
    } catch (e) {
      debugPrint('[SettingsService] getRaw($key) error: $e');
      return null;
    }
  }

  Future<void> _setRaw(String key, String value) async {
    try {
      await _db.customStatement(
        'INSERT INTO app_settings (key, value, updated_at)'
        ' VALUES (?, ?, ?)'
        ' ON CONFLICT(key) DO UPDATE SET value = excluded.value,'
        '   updated_at = excluded.updated_at',
        [key, value, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('[SettingsService] setRaw($key) error: $e');
    }
  }

  // ── Typed helpers ─────────────────────────────────────────────────────────

  Future<bool> _getBool(String key, {required bool fallback}) async {
    final v = await _getRaw(key);
    if (v == null) return fallback;
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<double> _getDouble(String key, {required double fallback}) async {
    final v = await _getRaw(key);
    return (v == null) ? fallback : (double.tryParse(v) ?? fallback);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Whether the loyalty / points system is enabled.
  /// Falling back to [true] preserves backward-compatible behaviour.
  Future<bool> isLoyaltyEnabled() =>
      _getBool(SettingsKeys.loyaltyEnabled, fallback: true);

  Future<void> setLoyaltyEnabled(bool enabled) =>
      _setRaw(SettingsKeys.loyaltyEnabled, enabled ? '1' : '0');

  /// Points earned per 1 unit of currency spent.
  /// Falls back to [LoyaltyConfig.pointsPerCurrency].
  Future<double> getPointsPerCurrency() => _getDouble(
        SettingsKeys.pointsPerCurrency,
        fallback: LoyaltyConfig.pointsPerCurrency,
      );

  Future<void> setPointsPerCurrency(double v) =>
      _setRaw(SettingsKeys.pointsPerCurrency, v.toString());

  /// Monetary value of a single loyalty point when redeemed.
  /// Falls back to [LoyaltyConfig.redemptionValue].
  Future<double> getRedemptionValue() => _getDouble(
        SettingsKeys.redemptionValue,
        fallback: LoyaltyConfig.redemptionValue,
      );

  Future<void> setRedemptionValue(double v) =>
      _setRaw(SettingsKeys.redemptionValue, v.toString());

  /// Store details for receipts
  Future<String> getStoreName() async =>
      await _getRaw(SettingsKeys.storeName) ?? 'ليز POS';

  Future<void> setStoreName(String v) => _setRaw(SettingsKeys.storeName, v);

  Future<String?> getStoreLogoPath() async =>
      await _getRaw(SettingsKeys.storeLogoPath);

  Future<void> setStoreLogoPath(String? v) async {
    if (v == null || v.isEmpty) {
      await _db.customStatement('DELETE FROM app_settings WHERE key = ?', [SettingsKeys.storeLogoPath]);
    } else {
      await _setRaw(SettingsKeys.storeLogoPath, v);
    }
  }

  Future<String?> getPhone() async => await _getRaw(SettingsKeys.phone);

  Future<void> setPhone(String? v) async {
    if (v == null || v.isEmpty) {
      await _db.customStatement('DELETE FROM app_settings WHERE key = ?', [SettingsKeys.phone]);
    } else {
      await _setRaw(SettingsKeys.phone, v);
    }
  }

  Future<String?> getAddress() async => await _getRaw(SettingsKeys.address);

  Future<void> setAddress(String? v) async {
    if (v == null || v.isEmpty) {
      await _db.customStatement('DELETE FROM app_settings WHERE key = ?', [SettingsKeys.address]);
    } else {
      await _setRaw(SettingsKeys.address, v);
    }
  }

  // ── Snapshot (load all at once for the UI/engine) ─────────────────────────

  /// Load all loyalty configuration in a single batch.
  /// Used by [LoyaltyService] at the start of each operation.
  Future<LoyaltySettings> loadLoyaltySettings() async {
    final results = await Future.wait([
      isLoyaltyEnabled(),
      getPointsPerCurrency(),
      getRedemptionValue(),
    ]);
    return LoyaltySettings(
      enabled: results[0] as bool,
      pointsPerCurrency: results[1] as double,
      redemptionValue: results[2] as double,
    );
  }
}

// ── Value object ──────────────────────────────────────────────────────────────

/// Immutable snapshot of all loyalty-related settings.
class LoyaltySettings {
  final bool enabled;
  final double pointsPerCurrency;
  final double redemptionValue;

  const LoyaltySettings({
    required this.enabled,
    required this.pointsPerCurrency,
    required this.redemptionValue,
  });

  /// Compile-time defaults — used as fallback in LoyaltyService.
  static const LoyaltySettings defaults = LoyaltySettings(
    enabled: true,
    pointsPerCurrency: LoyaltyConfig.pointsPerCurrency,
    redemptionValue: LoyaltyConfig.redemptionValue,
  );

  double earnedPoints(double amount) =>
      enabled ? (amount * pointsPerCurrency).floorToDouble() : 0;

  double redemptionDiscount(double points) =>
      enabled ? points * redemptionValue : 0;

  double maxRedeemable(double availablePoints, double invoiceTotal) {
    if (!enabled || availablePoints <= 0) return 0;
    final maxByTotal = (invoiceTotal / redemptionValue).floorToDouble();
    return availablePoints < maxByTotal ? availablePoints : maxByTotal;
  }
}
