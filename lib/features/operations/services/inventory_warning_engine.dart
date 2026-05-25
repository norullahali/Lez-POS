import '../../inventory/repositories/inventory_repository.dart';
import '../config/operations_thresholds.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'alert_builder.dart';

class InventoryWarningEngine {
  InventoryWarningEngine(this._repo, this._inventory);

  final OperationsIntelligenceRepository _repo;
  final InventoryRepository _inventory;

  Future<List<OperationalAlert>> evaluate() async {
    final alerts = <OperationalAlert>[];
    final now = DateTime.now();

    final lowStock = await _inventory.getLowStockProducts();
    for (final row in lowStock.take(OperationsThresholds.lowStockDisplayLimit)) {
      final id = row['id'] as int;
      final stock = (row['current_stock'] as num).toDouble();
      final min = (row['min_stock'] as num).toDouble();
      alerts.add(OperationalAlertBuilder.create(
        id: 'low_stock_$id',
        type: OperationalAlertType.lowStock,
        severity: stock <= 0
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'مخزون منخفض: ${row['name']}',
        description: 'الكمية الحالية $stock (الحد الأدنى $min)',
        reason: 'المخزون الحالي ($stock) ≤ الحد الأدنى ($min)',
        createdAt: now,
        entityType: 'product',
        entityId: id,
        actionLabel: 'عرض المخزن',
        actionRoute: '/inventory',
      ));
    }

    final dead = await _repo.fetchDeadStockProducts(days: OperationsThresholds.deadStockDays);
    for (final row in dead.take(OperationsThresholds.deadStockDisplayLimit)) {
      final id = row['id'] as int;
      alerts.add(OperationalAlertBuilder.create(
        id: 'dead_stock_$id',
        type: OperationalAlertType.deadStock,
        severity: OperationalAlertSeverity.warning,
        title: 'مخزون راكد: ${row['name']}',
        description: 'لا مبيعات خلال ${OperationsThresholds.deadStockDays} يوماً مع مخزون ${row['current_stock']}',
        reason: 'لا توجد حركة مبيعات خلال آخر ${OperationsThresholds.deadStockDays} يوماً رغم وجود مخزون',
        createdAt: now,
        entityType: 'product',
        entityId: id,
        actionLabel: 'التقارير',
        actionRoute: '/reports',
      ));
    }

    final overstock = await _repo.fetchOverstockRiskProducts();
    for (final row in overstock.take(OperationsThresholds.overstockDisplayLimit)) {
      final id = row['id'] as int;
      alerts.add(OperationalAlertBuilder.create(
        id: 'overstock_$id',
        type: OperationalAlertType.overstockRisk,
        severity: OperationalAlertSeverity.info,
        title: 'خطر تكدس: ${row['name']}',
        description: 'مخزون مرتفع مع حركة بيع ضعيفة',
        reason: 'المخزون يتجاوز ${OperationsThresholds.overstockMinMultiplier}× الحد الأدنى مع مبيعات <${(OperationsThresholds.overstockSalesRatio * 100).toInt()}% خلال ${OperationsThresholds.overstockLookbackDays} يوماً',
        createdAt: now,
        entityType: 'product',
        entityId: id,
        actionRoute: '/inventory',
      ));
    }

    return alerts;
  }
}