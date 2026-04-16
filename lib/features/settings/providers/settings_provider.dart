// lib/features/settings/providers/settings_provider.dart
//
// Riverpod providers for SettingsService and live loyalty settings.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/settings_service.dart';

/// Singleton SettingsService.
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(AppDatabase.instance);
});

/// Live snapshot of all loyalty settings from the database.
/// Invalidate this provider after saving changes to reload everywhere.
final loyaltySettingsProvider = FutureProvider<LoyaltySettings>((ref) {
  return ref.watch(settingsServiceProvider).loadLoyaltySettings();
});
