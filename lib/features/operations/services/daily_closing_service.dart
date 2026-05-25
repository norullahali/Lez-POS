import '../models/daily_closing_summary.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'inventory_warning_engine.dart';

class DailyClosingService {
  DailyClosingService(this._repo, this._inventoryEngine);

  final OperationsIntelligenceRepository _repo;
  final InventoryWarningEngine _inventoryEngine;

  Future<DailyClosingSummary> buildSummary([DateTime? date]) async {
    final target = date ?? DateTime.now();
    final metrics = await _repo.fetchDailyClosingMetrics(target);
    final inventoryAlerts = (await _inventoryEngine.evaluate()).length;

    final totalSales = (metrics['total_sales'] as num?)?.toDouble() ?? 0;
    final totalReturns = (metrics['total_returns'] as num?)?.toDouble() ?? 0;
    final returnRate = totalSales > 0 ? (totalReturns / totalSales) * 100 : 0.0;

    final insightLines = <String>[
      'مبيعات اليوم: ${totalSales.toStringAsFixed(0)} (${metrics['invoice_count'] ?? 0} فاتورة)',
      'مرتجعات: ${totalReturns.toStringAsFixed(0)} (${returnRate.toStringAsFixed(1)}%)',
      if (metrics['top_product'] != null)
        'أفضل منتج: ${metrics['top_product']}',
      if (metrics['weak_category'] != null)
        'أضعف فئة: ${metrics['weak_category']}',
      if (metrics['top_cashier'] != null)
        'أفضل كاشير: ${metrics['top_cashier']}',
      if ((metrics['session_mismatch_count'] as int? ?? 0) > 0)
        'جلسات بفرق نقدي: ${metrics['session_mismatch_count']}',
    ];

    return DailyClosingSummary(
      date: target,
      totalSales: totalSales,
      invoiceCount: (metrics['invoice_count'] as int?) ?? 0,
      totalReturns: totalReturns,
      returnRatePercent: returnRate,
      inventoryAlerts: inventoryAlerts,
      debtReceivable: (metrics['receivable'] as num?)?.toDouble() ?? 0,
      debtPayable: (metrics['payable'] as num?)?.toDouble() ?? 0,
      topProductName: metrics['top_product'] as String?,
      weakCategoryName: metrics['weak_category'] as String?,
      topCashierName: metrics['top_cashier'] as String?,
      sessionMismatchCount: (metrics['session_mismatch_count'] as int?) ?? 0,
      insightLines: insightLines,
    );
  }
}
