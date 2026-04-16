// lib/features/loyalty/providers/loyalty_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../services/loyalty_service.dart';

/// Singleton [LoyaltyService] — receives both DB and SettingsService.
/// Automatically rebuilds when [loyaltySettingsProvider] is invalidated
/// (i.e. after the owner changes loyalty settings), ensuring POS uses
/// the latest rates without an app restart.
final loyaltyServiceProvider = Provider<LoyaltyService>((ref) {
  // Watch the settings provider so this provider rebuilds when settings change.
  // The LoyaltyService itself fetches fresh settings on every call, but
  // watching here also rebuilds any UI that watches loyaltyServiceProvider.
  ref.watch(loyaltySettingsProvider);
  final settingsSvc = ref.watch(settingsServiceProvider);
  return LoyaltyService(AppDatabase.instance, settingsSvc);
});

/// Live balance of loyalty points for a specific customer.
final customerLoyaltyPointsProvider =
    FutureProvider.family<double, int>((ref, customerId) async {
  if (customerId == 1) return 0.0;
  return ref.watch(loyaltyServiceProvider).getPoints(customerId);
});
