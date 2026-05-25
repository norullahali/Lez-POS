import '../config/operations_thresholds.dart';
import '../models/cashier_behavior_models.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_severity.dart';
import '../models/operational_alert_type.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'alert_builder.dart';

class CashierBehaviorMonitor {
  CashierBehaviorMonitor(this._repo);

  final OperationsIntelligenceRepository _repo;

  Future<List<CashierBehaviorRow>> evaluateRows() async {
    final raw = await _repo.fetchCashierBehaviorRows();
    return raw.map((row) {
      final flags = <String>[];
      final refundCount = (row['refund_count'] as int?) ?? 0;
      final refundAmount = (row['refund_amount'] as num).toDouble();
      final discountInvoices = (row['discount_invoices'] as int?) ?? 0;
      final invoiceCount = (row['invoice_count'] as int?) ?? 0;
      final mismatchCount = (row['session_mismatch_count'] as int?) ?? 0;
      final sessionMinutes = (row['session_minutes'] as num).toDouble();

      if (refundCount >= OperationsThresholds.suspiciousRefundCount) flags.add('مرتجعات متكررة');
      if (refundAmount >= 200) flags.add('قيمة مرتجعات مرتفعة');
      if (invoiceCount > 0 &&
          discountInvoices / invoiceCount > OperationsThresholds.discountInvoiceRatio) {
        flags.add('خصومات مفرطة');
      }
      if (mismatchCount > 0) flags.add('فرق جلسة');
      if (sessionMinutes > 0 &&
          sessionMinutes < OperationsThresholds.shortSessionMinutes &&
          invoiceCount > 0) {
        flags.add('جلسة قصيرة');
      }
      if (invoiceCount == 0 && refundCount > 0) {
        flags.add('مرتجعات بدون مبيعات');
      }

      return CashierBehaviorRow(
        userId: row['user_id'] as int,
        name: row['name'] as String? ?? 'مستخدم',
        refundCount: refundCount,
        refundAmount: refundAmount,
        invoiceCount: invoiceCount,
        averageInvoice: (row['avg_invoice'] as num).toDouble(),
        discountInvoices: discountInvoices,
        sessionMismatchCount: mismatchCount,
        inactivityMinutes: sessionMinutes,
        flags: flags,
      );
    }).where((r) => r.flags.isNotEmpty).toList();
  }

  Future<List<OperationalAlert>> evaluateAlerts() async {
    final rows = await evaluateRows();
    final now = DateTime.now();
    return rows.take(8).map((row) {
      return OperationalAlertBuilder.create(
        id: 'cashier_anomaly_${row.userId}',
        type: OperationalAlertType.cashierAnomaly,
        severity: row.flags.length >= 2
            ? OperationalAlertSeverity.critical
            : OperationalAlertSeverity.warning,
        title: 'سلوك كاشير: ${row.name}',
        description: row.flags.join(' • '),
        reason: 'تم رصد: ${row.flags.join('، ')}',
        createdAt: now,
        entityType: 'user',
        entityId: row.userId,
        actionLabel: 'الجدول الزمني',
        actionRoute: '/activity/timeline',
      );
    }).toList();
  }
}