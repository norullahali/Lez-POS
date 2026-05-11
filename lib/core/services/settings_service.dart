// lib/core/services/settings_service.dart

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import '../constants/loyalty_config.dart';
import '../database/app_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Setting key constants ─────────────────────────────────────────────────────

abstract class SettingsKeys {
  static const String loyaltyEnabled = 'loyalty_enabled';
  static const String pointsPerCurrency = 'points_per_currency';
  static const String redemptionValue = 'redemption_value';
  static const String storeName = 'store_name';
  static const String storeLogoPath = 'store_logo_path';
  static const String phone = 'phone';
  static const String address = 'address';
}

// ── Service ───────────────────────────────────────────────────────────────────

class SettingsService {
  final AppDatabase _db;
  SettingsService(this._db);

  Future<void> setPrinterType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_type', type);
  }

  Future<String> getPrinterType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_type') ?? 'pdf';
  }

  Future<String?> getInvoiceFooter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('invoice_footer');
  }

  Future<bool> getShowTax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('show_tax') ?? true;
  }

  // ── Low-level helpers ─────────────────────────────────────────────────────

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
        ' updated_at = excluded.updated_at',
        [key, value, DateTime.now().millisecondsSinceEpoch],
      );
    } catch (e) {
      debugPrint('[SettingsService] setRaw($key) error: $e');
    }
  }

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

  Future<bool> isLoyaltyEnabled() =>
      _getBool(SettingsKeys.loyaltyEnabled, fallback: true);

  Future<void> setLoyaltyEnabled(bool enabled) =>
      _setRaw(SettingsKeys.loyaltyEnabled, enabled ? '1' : '0');

  Future<double> getPointsPerCurrency() => _getDouble(
        SettingsKeys.pointsPerCurrency,
        fallback: LoyaltyConfig.pointsPerCurrency,
      );

  Future<void> setPointsPerCurrency(double v) =>
      _setRaw(SettingsKeys.pointsPerCurrency, v.toString());

  Future<double> getRedemptionValue() => _getDouble(
        SettingsKeys.redemptionValue,
        fallback: LoyaltyConfig.redemptionValue,
      );

  Future<void> setRedemptionValue(double v) =>
      _setRaw(SettingsKeys.redemptionValue, v.toString());

  // ── Store Info ─────────────────────────────────────────────────────────────

  Future<String> getStoreName() async =>
      await _getRaw(SettingsKeys.storeName) ?? 'Lez POS';

  Future<void> setStoreName(String v) => _setRaw(SettingsKeys.storeName, v);

  Future<String?> getStoreLogoPath() async =>
      await _getRaw(SettingsKeys.storeLogoPath);

  Future<void> setStoreLogoPath(String? v) async {
    if (v == null || v.isEmpty) {
      await _db.customStatement(
        'DELETE FROM app_settings WHERE key = ?',
        [SettingsKeys.storeLogoPath],
      );
    } else {
      await _setRaw(SettingsKeys.storeLogoPath, v);
    }
  }

  Future<String?> getPhone() async => await _getRaw(SettingsKeys.phone);

  Future<void> setPhone(String? v) async {
    if (v == null || v.isEmpty) {
      await _db.customStatement(
        'DELETE FROM app_settings WHERE key = ?',
        [SettingsKeys.phone],
      );
    } else {
      await _setRaw(SettingsKeys.phone, v);
    }
  }

  Future<String?> getAddress() async => await _getRaw(SettingsKeys.address);

  Future<void> setAddress(String? v) async {
    if (v == null || v.isEmpty) {
      await _db.customStatement(
        'DELETE FROM app_settings WHERE key = ?',
        [SettingsKeys.address],
      );
    } else {
      await _setRaw(SettingsKeys.address, v);
    }
  }

  // ── Snapshot ─────────────────────────────────────────────────────────────
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

// ── Value object ─────────────────────────────────────────────────────────────
class LoyaltySettings {
  final bool enabled;
  final double pointsPerCurrency;
  final double redemptionValue;

  const LoyaltySettings({
    required this.enabled,
    required this.pointsPerCurrency,
    required this.redemptionValue,
  });

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

Future<void> setPrinterType(String type) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('printer_type', type);
}

Future<String> getPrinterType() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('printer_type') ?? 'pdf'; // default
}
