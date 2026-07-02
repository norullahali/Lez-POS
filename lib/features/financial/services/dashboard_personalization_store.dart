import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard_personalization.dart';

/// Presentation-only persistence for Financial Dashboard personalization (Phase 5.3.9).
///
/// **Ownership:** called exclusively by [FinancialDashboardScreen] load/save paths.
///
/// **Architecture:** UI -> [DashboardPersonalizationStore] -> SharedPreferences.
///
/// **Presentation boundary:** stores layout preferences only — no analytics, filters,
/// export, repositories, providers, or SQL.
///
/// **Load lifecycle:** one async read per dashboard open; null, empty, or malformed
/// JSON falls back to [DashboardPersonalization] defaults.
///
/// **Save lifecycle:** encodes via [DashboardPersonalization.toJson]; skips write
/// when the JSON string is unchanged (store-level duplicate-write avoidance).
/// Screen-level dedup via [_lastPersistedPersonalization] runs before this call.
///
/// **Key versioning:** [prefsKey] suffix `_v1` allows future schema migration by
/// introducing a new key without breaking existing installs.
class DashboardPersonalizationStore {
  DashboardPersonalizationStore._();

  /// SharedPreferences key for the v1 personalization JSON payload.
  static const prefsKey = 'financial_dashboard_personalization_v1';

  /// Loads saved personalization or returns [DashboardPersonalization] defaults.
  static Future<DashboardPersonalization> load() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeStored(prefs.getString(prefsKey));
  }

  /// Persists [value]; skips write when encoded payload is unchanged.
  static Future<void> save(DashboardPersonalization value) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(value.toJson());
    final existing = prefs.getString(prefsKey);
    if (existing == encoded) return;
    await prefs.setString(prefsKey, encoded);
  }

  /// Decodes stored JSON — null, empty, or invalid payloads return defaults.
  static DashboardPersonalization _decodeStored(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const DashboardPersonalization();
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return DashboardPersonalization.fromJson(map);
    } catch (_) {
      return const DashboardPersonalization();
    }
  }
}