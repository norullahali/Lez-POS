// lib/core/services/settings_service.dart

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import '../constants/loyalty_config.dart';
import '../database/app_database.dart';
import '../printing/printer_config.dart';
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
  // Invoice display
  static const String invoiceFooter = 'invoice_footer';
  static const String showTax = 'show_tax';
}

// ── Service ───────────────────────────────────────────────────────────────────

class SettingsService {
  final AppDatabase _db;
  SettingsService(this._db);

  // ── Printer configuration ──────────────────────────────────────────────────

  /// Loads the full printer configuration from app_settings.
  ///
  /// Falls back to [PrinterConfig.defaults] when no settings are persisted.
  /// For backward compatibility, if [printer_type] is absent from the DB it
  /// also checks SharedPreferences (where it was stored in older versions).
  Future<PrinterConfig> getPrinterConfig() async {
    // Resolve printer type — check DB first, then legacy SharedPrefs.
    String? typeRaw = await _getRaw(PrinterSettingsKeys.printerType);
    if (typeRaw == null || typeRaw.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      typeRaw = prefs.getString('printer_type');
    }
    final type = PrinterType.values.firstWhere(
      (t) => t.name == typeRaw,
      orElse: () => PrinterType.pdf,
    );

    final printerName = await _getRaw(PrinterSettingsKeys.printerName);
    final printerIp = await _getRaw(PrinterSettingsKeys.printerIp);
    final portRaw = await _getRaw(PrinterSettingsKeys.printerPort);
    final printerPort = int.tryParse(portRaw ?? '') ?? 9100;
    final bluetoothDeviceId = await _getRaw(PrinterSettingsKeys.bluetoothDeviceId);
    final paperSizeRaw = await _getRaw(PrinterSettingsKeys.receiptPaperSize);
    final paperSize = PrinterConfig.parsePaperSize(paperSizeRaw);

    return PrinterConfig(
      type: type,
      printerName: printerName,
      printerIp: printerIp,
      printerPort: printerPort,
      bluetoothDeviceId: bluetoothDeviceId,
      paperSize: paperSize,
    );
  }

  /// Persists all printer settings to app_settings.
  Future<void> savePrinterConfig(PrinterConfig config) async {
    await _setRaw(PrinterSettingsKeys.printerType, config.type.name);
    await _setRaw(PrinterSettingsKeys.receiptPaperSize,
        PrinterConfig.paperSizeToString(config.paperSize));
    if (config.printerName != null && config.printerName!.isNotEmpty) {
      await _setRaw(PrinterSettingsKeys.printerName, config.printerName!);
    }
    if (config.printerIp != null && config.printerIp!.isNotEmpty) {
      await _setRaw(PrinterSettingsKeys.printerIp, config.printerIp!);
    }
    await _setRaw(PrinterSettingsKeys.printerPort, config.printerPort.toString());
    if (config.bluetoothDeviceId != null && config.bluetoothDeviceId!.isNotEmpty) {
      await _setRaw(PrinterSettingsKeys.bluetoothDeviceId, config.bluetoothDeviceId!);
    }
    debugPrint('[SettingsService] Printer config saved: $config');
  }

  /// Legacy setter — kept for backward compatibility.
  /// Prefer [savePrinterConfig] going forward.
  Future<void> setPrinterType(String type) async {
    await _setRaw(PrinterSettingsKeys.printerType, type);
    // Also update SharedPreferences for any code still reading from there.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_type', type);
  }

  /// Legacy getter — kept for backward compatibility.
  /// Prefer [getPrinterConfig] going forward.
  Future<String> getPrinterType() async {
    final fromDb = await _getRaw(PrinterSettingsKeys.printerType);
    if (fromDb != null && fromDb.isNotEmpty) return fromDb;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('printer_type') ?? 'pdf';
  }

  // ── Invoice display ────────────────────────────────────────────────────────

  Future<String?> getInvoiceFooter() => _getRaw(SettingsKeys.invoiceFooter);

  Future<void> setInvoiceFooter(String? v) async {
    if (v == null || v.isEmpty) {
      await _db.customStatement(
          'DELETE FROM app_settings WHERE key = ?', [SettingsKeys.invoiceFooter]);
    } else {
      await _setRaw(SettingsKeys.invoiceFooter, v);
    }
  }

  Future<bool> getShowTax() async {
    final v = await _getRaw(SettingsKeys.showTax);
    if (v == null) return true;
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<void> setShowTax(bool v) => _setRaw(SettingsKeys.showTax, v ? '1' : '0');

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

// Legacy top-level functions removed — use SettingsService.setPrinterType /
// SettingsService.getPrinterConfig instead.
