import '../cache/automation_cache.dart';
import '../models/purchase_recommendation.dart';
import '../models/reorder_suggestion.dart';
import 'reorder_suggestion_service.dart';

class PurchaseRecommendationService {
  PurchaseRecommendationService(this._reorder);
  final ReorderSuggestionService _reorder;

  Future<List<SupplierPurchaseRecommendation>> generate() async {
    return AutomationCache.memo('purchase_recs', () async {
      final suggestions = await _reorder.generate();
      final urgent = suggestions.where((s) => s.urgency != ReorderUrgency.safe).toList();
      final bySupplier = <String, List<ReorderSuggestion>>{};
      for (final s in urgent) {
        final key = s.supplierName ?? 'بدون مورد';
        bySupplier.putIfAbsent(key, () => []).add(s);
      }
      return bySupplier.entries.map((e) {
        final lines = e.value.map((s) => PurchaseRecommendationLine(
              productId: s.productId,
              productName: s.productName,
              suggestedQty: s.suggestedQty,
              unitCost: 0,
              explanation: s.explanation,
            )).toList();
        final avgDays = e.value.isEmpty ? 0.0 : e.value.map((v) => v.daysRemaining).reduce((a, b) => a + b) / e.value.length;
        return SupplierPurchaseRecommendation(
          supplierId: e.value.first.supplierId,
          supplierName: e.key,
          lines: lines,
          projectedCoverageDays: avgDays + 7,
        );
      }).toList()
        ..sort((a, b) => b.estimatedTotal.compareTo(a.estimatedTotal));
    });
  }
}