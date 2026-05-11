// lib/features/settings/providers/settings_provider.dart
//
// Riverpod providers for SettingsService, loyalty settings,
// and printer configuration.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/printing/printer_config.dart';
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

/// Current printer configuration loaded from app_settings.
///
/// Returns [PrinterConfig.defaults] while loading or on error.
/// Invalidate after calling [SettingsService.savePrinterConfig] to reload.
///
/// Usage:
///   final config = ref.watch(printerConfigProvider).valueOrNull
///                  ?? PrinterConfig.defaults;
///   await PrintManager(config).print(invoiceData);
final printerConfigProvider = FutureProvider<PrinterConfig>((ref) {
  return ref.watch(settingsServiceProvider).getPrinterConfig();
});
