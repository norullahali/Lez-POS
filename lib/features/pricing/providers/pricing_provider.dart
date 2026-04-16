// lib/features/pricing/providers/pricing_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../models/pricing_rule_model.dart';
import '../services/pricing_engine.dart';

// ── Singleton engine ──────────────────────────────────────────────────────────
final _engine = PricingEngine();

/// Async notifier that loads all pricing rules from DB and keeps them in memory.
class PricingNotifier extends AsyncNotifier<List<PricingRuleModel>> {
  @override
  Future<List<PricingRuleModel>> build() async {
    final rows = await AppDatabase.instance.pricingDao.getActiveRulesRaw();
    final rules = rows.map(PricingRuleModel.fromMap).toList();
    _engine.loadRules(rules);
    return rules;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final rows = await AppDatabase.instance.pricingDao.getActiveRulesRaw();
      final rules = rows.map(PricingRuleModel.fromMap).toList();
      _engine.loadRules(rules);
      return rules;
    });
  }
}

final pricingProvider =
    AsyncNotifierProvider<PricingNotifier, List<PricingRuleModel>>(
  PricingNotifier.new,
);

/// Synchronous provider: always returns the current engine instance.
/// Stays valid even while [pricingProvider] is loading.
final pricingEngineProvider = Provider<PricingEngine>((ref) {
  // Watch so that engine reloads when rules change
  ref.watch(pricingProvider);
  return _engine;
});

// ── Admin helpers ─────────────────────────────────────────────────────────────

/// All rules (active + inactive) for the admin list screen.
final allPricingRulesProvider = FutureProvider<List<PricingRuleModel>>((ref) async {
  // Invalidated by pricingProvider reload
  ref.watch(pricingProvider);
  final rows = await AppDatabase.instance.pricingDao.getAllRulesRaw();
  return rows.map(PricingRuleModel.fromMap).toList();
});
