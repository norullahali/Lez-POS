// lib/core/database/daos/app_settings_dao.dart
//
// Full CRUD DAO for the app_settings table.
// Provides typed read/write helpers for common value types.

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_settings_table.dart';

part 'app_settings_dao.g.dart';

@DriftAccessor(tables: [AppSettings])
class AppSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$AppSettingsDaoMixin {
  AppSettingsDao(super.db);

  // ── Raw access ────────────────────────────────────────────────────────────

  /// Returns the raw string value for [key], or null if the key doesn't exist.
  Future<String?> getRaw(String key) async {
    final row = await (select(appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Upsert a setting key/value pair.
  Future<void> setRaw(String key, String value,
      {String? description}) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion(
        key: Value(key),
        value: Value(value),
        description: description != null
            ? Value(description)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Watch a single setting for live UI updates.
  Stream<String?> watchRaw(String key) {
    return (select(appSettings)..where((s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  /// Watch the entire settings table (useful for the settings screen).
  Stream<List<AppSetting>> watchAll() =>
      (select(appSettings)..orderBy([(s) => OrderingTerm.asc(s.key)])).watch();

  Future<List<AppSetting>> getAll() =>
      (select(appSettings)..orderBy([(s) => OrderingTerm.asc(s.key)])).get();

  // ── Typed helpers ─────────────────────────────────────────────────────────

  Future<bool?> getBool(String key) async {
    final v = await getRaw(key);
    if (v == null) return null;
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<void> setBool(String key, bool value,
      {String? description}) =>
      setRaw(key, value ? '1' : '0', description: description);

  Future<double?> getDouble(String key) async {
    final v = await getRaw(key);
    return v == null ? null : double.tryParse(v);
  }

  Future<void> setDouble(String key, double value,
      {String? description}) =>
      setRaw(key, value.toString(), description: description);

  // ── Deletion (rarely needed) ──────────────────────────────────────────────

  Future<void> deleteSetting(String key) async {
    await (delete(appSettings)..where((s) => s.key.equals(key))).go();
  }
}
