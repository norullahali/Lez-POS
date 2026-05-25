import '../config/operations_thresholds.dart';
import '../models/operational_alert.dart';
import '../models/operational_alert_type.dart';
import '../models/store_operational_health.dart';
import '../repositories/operations_intelligence_repository.dart';
import 'operational_evaluation_cache.dart';

class OperationalHealthService {
  OperationalHealthService(this._repo);

  final OperationsIntelligenceRepository _repo;

  Future<StoreOperationalHealth> evaluate({List<OperationalAlert>? alerts}) async {
    final now = DateTime.now();
    var score = 100;
    final factors = <String>[];

    final returnRate = await OperationalEvaluationCache.memo(
      'return_rate',
      () => _repo.fetchReturnRateComparison(),
    );
    final todayRate = (returnRate['today_rate'] as num?)?.toDouble() ?? 0;
    if (todayRate > 10) {
      score -= 15;
      factors.add('مرتجعات مرتفعة (${todayRate.toStringAsFixed(1)}%)');
    } else if (todayRate > 5) {
      score -= 8;
      factors.add('مرتجعات فوق المتوسط');
    }

    final inventoryRisk = alerts
            ?.where((a) =>
                a.type == OperationalAlertType.lowStock ||
                a.type == OperationalAlertType.expiryCritical ||
                a.type == OperationalAlertType.lowStockPrediction)
            .length ??
        0;
    if (inventoryRisk >= 5) {
      score -= 20;
      factors.add('مخاطر مخزون ($inventoryRisk)');
    } else if (inventoryRisk > 0) {
      score -= 10;
      factors.add('تنبيهات مخزون');
    }

    final sessions = await OperationalEvaluationCache.memo(
      'session_mismatch',
      () => _repo.fetchSessionMismatches(
        minDiff: OperationsThresholds.sessionMismatchMinDiff,
      ),
    );
    if (sessions.length >= 3) {
      score -= 15;
      factors.add('فروقات جلسات (${sessions.length})');
    } else if (sessions.isNotEmpty) {
      score -= 7;
      factors.add('فرق جلسة نقدي');
    }

    final suspicious = alerts
            ?.where((a) =>
                a.type == OperationalAlertType.suspiciousRefund ||
                a.type == OperationalAlertType.unusualActivity ||
                a.type == OperationalAlertType.cashierAnomaly)
            .length ??
        0;
    if (suspicious >= 3) {
      score -= 18;
      factors.add('نشاط مشبوه ($suspicious)');
    } else if (suspicious > 0) {
      score -= 8;
    }

    final debts = await OperationalEvaluationCache.memo(
      'overdue_debts',
      () => _repo.fetchOverdueDebts(
        minBalance: OperationsThresholds.overdueDebtMinBalance,
      ),
    );
    if (debts.length >= 5) {
      score -= 12;
      factors.add('ذمم متأخرة (${debts.length})');
    }

    score = score.clamp(0, 100);
    final status = _statusFor(score);

    return StoreOperationalHealth(
      score: score,
      status: status,
      factors: factors.isEmpty ? ['لا توجد عوامل خطر بارزة'] : factors,
      evaluatedAt: now,
    );
  }

  static StoreHealthStatus _statusFor(int score) {
    if (score >= 90) return StoreHealthStatus.excellent;
    if (score >= 75) return StoreHealthStatus.healthy;
    if (score >= 55) return StoreHealthStatus.warning;
    return StoreHealthStatus.critical;
  }
}