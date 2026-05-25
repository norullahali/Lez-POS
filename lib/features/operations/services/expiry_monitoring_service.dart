import '../../inventory/repositories/inventory_repository.dart';
import '../models/expiry_alert.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'alert_builder.dart';

class ExpiryMonitoringService {
  ExpiryMonitoringService(this._repo, this._inventory);

  final OperationsIntelligenceRepository _repo;
  final InventoryRepository _inventory;

  Future<ExpiryMonitoringSnapshot> snapshot() async {
    final enabled = await _repo.isExpiryTrackingEnabled();
    if (!enabled) return ExpiryMonitoringSnapshot.empty;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = <ExpiryAlertItem>[];

    final expiring = await _inventory.getExpiringProducts(30);
    for (final row in expiring) {
      final expiryRaw = row['expiry_date'];
      DateTime? expiry;
      if (expiryRaw is DateTime) {
        expiry = expiryRaw;
      } else if (expiryRaw is int) {
        expiry = DateTime.fromMillisecondsSinceEpoch(expiryRaw);
      } else if (expiryRaw is String) {
        expiry = DateTime.tryParse(expiryRaw);
      }
      if (expiry == null) continue;

      final daysLeft = expiry.difference(today).inDays;
      ExpiryAlertLevel level;
      if (daysLeft < 0) {
        level = ExpiryAlertLevel.expired;
      } else if (daysLeft <= 3) {
        level = ExpiryAlertLevel.critical;
      } else if (daysLeft <= 7) {
        level = ExpiryAlertLevel.warning;
      } else {
        level = ExpiryAlertLevel.none;
      }
      if (level == ExpiryAlertLevel.none) continue;

      items.add(ExpiryAlertItem(
        productId: row['product_id'] as int,
        productName: row['product_name'] as String? ?? 'منتج',
        expiryDate: expiry,
        level: level,
        batchId: row['id'] as int?,
      ));
    }

    return ExpiryMonitoringSnapshot(trackingEnabled: true, items: items);
  }

  Future<List<OperationalAlert>> evaluateAlerts() async {
    final snap = await snapshot();
    if (!snap.trackingEnabled) return [];

    final now = DateTime.now();
    return snap.items.map((item) {
      final type = item.level == ExpiryAlertLevel.critical ||
              item.level == ExpiryAlertLevel.expired
          ? OperationalAlertType.expiryCritical
          : OperationalAlertType.expiryNear;
      final severity = item.level == ExpiryAlertLevel.expired ||
              item.level == ExpiryAlertLevel.critical
          ? OperationalAlertSeverity.critical
          : OperationalAlertSeverity.warning;

      return OperationalAlertBuilder.create(
        id: 'expiry_${item.productId}_${item.batchId ?? 0}',
        type: type,
        severity: severity,
        title: item.level == ExpiryAlertLevel.expired
            ? 'منتهي الصلاحية: ${item.productName}'
            : 'قرب انتهاء: ${item.productName}',
        description: 'تاريخ الصلاحية: ${item.expiryDate.toString().split(' ').first}',
        reason: item.level == ExpiryAlertLevel.expired
            ? 'المنتج تجاوز تاريخ الصلاحية'
            : 'المنتج ضمن نافذة انتهاء الصلاحية الحرجة',
        createdAt: now,
        entityType: 'product',
        entityId: item.productId,
        actionRoute: '/inventory',
      );
    }).toList();
  }
}