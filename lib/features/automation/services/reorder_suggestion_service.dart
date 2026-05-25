import '../cache/automation_cache.dart';
import '../models/reorder_suggestion.dart';
import '../repositories/automation_repository.dart';
import '../rules/operations_rules.dart';
import 'rules_engine_service.dart';

class ReorderSuggestionService {
  ReorderSuggestionService(this._repo);
  final AutomationRepository _repo;

  Future<List<ReorderSuggestion>> generate({int days = 7}) async {
    return AutomationCache.memo('reorder_$days', () async {
      final rows = await _repo.fetchProductVelocity(days: days);
      final out = <ReorderSuggestion>[];
      for (final row in rows) {
        final stock = (row['current_stock'] as num).toDouble();
        if (stock < 0) continue;
        final min = (row['min_stock'] as num).toDouble();
        final sold = (row['sold_qty'] as num).toDouble();
        final daily = sold / days;
        if (daily <= 0 && stock > min) continue;
        final daysLeft = daily > 0 ? stock / daily : 999.0;
        final urgency = _urgency(daysLeft, stock, min);
        if (urgency == ReorderUrgency.safe && stock > min) continue;
        final target = (min * 2).clamp(min + 1, min + daily * 14).toDouble();
        final suggested = (target - stock).clamp(1.0, daily * 21 + min).toDouble();
        final rules = RulesEngineService.evaluateReorder(daysRemaining: daysLeft, dailyRate: daily);
        final explanation = 'معدل ${daily.toStringAsFixed(2)}/يوم، متبقي ${daysLeft.toStringAsFixed(1)} يوم. '
            '${rules.where((r) => r.passed).map((r) => r.detail).join(' • ')}';
        out.add(ReorderSuggestion(
          productId: row['id'] as int,
          productName: row['name'] as String? ?? 'منتج',
          currentStock: stock,
          suggestedQty: suggested,
          urgency: urgency,
          daysRemaining: daysLeft,
          dailyRate: daily,
          explanation: explanation.trim(),
          supplierId: row['supplier_id'] as int?,
          supplierName: row['supplier_name'] as String?,
          priorityScore: _priority(urgency, daysLeft),
        ));
      }
      out.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
      return out.take(40).toList();
    });
  }

  ReorderUrgency _urgency(double days, double stock, double min) {
    if (stock <= 0 || days <= OperationsRules.reorderCriticalDays) return ReorderUrgency.critical;
    if (stock <= min || days <= OperationsRules.reorderUrgentDays) return ReorderUrgency.urgent;
    if (days <= 14) return ReorderUrgency.warning;
    return ReorderUrgency.safe;
  }

  int _priority(ReorderUrgency u, double days) => switch (u) {
        ReorderUrgency.critical => 95,
        ReorderUrgency.urgent => 80,
        ReorderUrgency.warning => 60,
        ReorderUrgency.safe => 30,
      } - days.clamp(0, 20).toInt();
}