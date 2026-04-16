// lib/core/database/tables/app_settings_table.dart
//
// A simple key/value store for application-wide settings.
// Values are always stored as TEXT — the DAO layer handles type conversion.

import 'package:drift/drift.dart';

class AppSettings extends Table {
  /// Auto-increment surrogate PK (makes Drift happy).
  IntColumn get id => integer().autoIncrement()();

  /// Unique setting key, e.g. 'loyalty_enabled', 'points_per_currency'.
  TextColumn get key => text().withLength(min: 1, max: 100).unique()();

  /// Serialised value (always stored as text; converted by DAO).
  TextColumn get value => text()();

  /// Human-readable description shown in UI (optional).
  TextColumn get description => text().nullable()();

  /// When this row was last updated.
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}
