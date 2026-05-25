import '../cache/automation_cache.dart';
import '../models/restock_plan_item.dart';
import '../models/reorder_suggestion.dart';
import '../repositories/automation_repository.dart';
import 'reorder_suggestion_service.dart';

class RestockPlanningService {
  RestockPlanningService(this._repo, this._reorder);
  final AutomationRepository _repo;
  final ReorderSuggestionService _reorder;

  Future<List<RestockPlanItem>> buildPlan() async {
    return AutomationCache.memo('restock_plan', () async {
      final suggestions = await _reorder.generate();
      final dead = await _repo.fetchProductVelocity(days: 30);
      final deadIds = dead.where((r) => (r['sold_qty'] as num) <= 0 && (r['current_stock'] as num) > 0).map((r) => r['id']).toSet();
      final items = <RestockPlanItem>[];
      for (final s in suggestions.take(25)) {
        final pressure = _pressure(s);
        items.add(RestockPlanItem(
          productId: s.productId,
          productName: s.productName,
          currentStock: s.currentStock,
          targetStock: s.currentStock + s.suggestedQty,
          pressure: pressure,
          scheduleHintAr: pressure == RestockPressure.critical ? 'اليوم' : 'خلال ${s.daysRemaining.toStringAsFixed(0)} يوم',
          explanation: s.explanation,
        ));
      }
      for (final id in deadIds.take(5)) {
        final row = dead.firstWhere((r) => r['id'] == id);
        items.add(RestockPlanItem(
          productId: id as int,
          productName: row['name'] as String? ?? 'منتج',
          currentStock: (row['current_stock'] as num).toDouble(),
          targetStock: (row['min_stock'] as num).toDouble(),
          pressure: RestockPressure.low,
          scheduleHintAr: 'مراجعة راكد',
          explanation: 'لا حركة 30 يوماً — تجنب إعادة التخزين',
        ));
      }
      return items;
    });
  }

  RestockPressure _pressure(ReorderSuggestion s) => switch (s.urgency) {
        ReorderUrgency.critical => RestockPressure.critical,
        ReorderUrgency.urgent => RestockPressure.high,
        ReorderUrgency.warning => RestockPressure.medium,
        ReorderUrgency.safe => RestockPressure.low,
      };
}