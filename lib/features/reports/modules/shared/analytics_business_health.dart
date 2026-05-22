import 'package:flutter/material.dart';

import 'advanced_analytics_models.dart';
import '../../core/models/report_metric_model.dart';

class BusinessHealthInsight {
  const BusinessHealthInsight({
    required this.title,
    required this.message,
    required this.semantic,
    required this.icon,
  });

  final String title;
  final String message;
  final ReportTrendSemantic semantic;
  final IconData icon;
}

/// Heuristic business-health signals (no AI / no external APIs).
class AnalyticsBusinessHealth {
  AnalyticsBusinessHealth._();

  static List<BusinessHealthInsight> evaluate({
    required ExecutiveDashboardData exec,
    ComparativeAnalyticsData? comparison,
    List<CategoryPerformanceRow>? categories,
    ProductVelocityData? velocity,
    List<EmployeePerformanceRow>? employees,
  }) {
    final insights = <BusinessHealthInsight>[];

    if (comparison != null) {
      if (comparison.revenueChangePercent >= 5) {
        insights.add(BusinessHealthInsight(
          title: 'نمو المبيعات',
          message: 'الإيراد ارتفع ${comparison.revenueChangePercent.toStringAsFixed(1)}% عن الفترة السابقة',
          semantic: ReportTrendSemantic.positive,
          icon: Icons.trending_up_rounded,
        ));
      } else if (comparison.revenueChangePercent <= -5) {
        insights.add(BusinessHealthInsight(
          title: 'تراجع المبيعات',
          message: 'الإيراد انخفض ${comparison.revenueChangePercent.abs().toStringAsFixed(1)}% — راجع العروض والمخزون',
          semantic: ReportTrendSemantic.negative,
          icon: Icons.trending_down_rounded,
        ));
      }
    }

    if (exec.returnRatePercent >= 10) {
      insights.add(BusinessHealthInsight(
        title: 'نسبة مرتجعات خطرة',
        message: 'نسبة المرتجعات ${exec.returnRatePercent.toStringAsFixed(1)}% — تحتاج متابعة فورية',
        semantic: ReportTrendSemantic.warning,
        icon: Icons.warning_amber_rounded,
      ));
    } else if (exec.returnRatePercent >= 5) {
      insights.add(BusinessHealthInsight(
        title: 'ارتفاع المرتجعات',
        message: 'نسبة المرتجعات ${exec.returnRatePercent.toStringAsFixed(1)}% — راقب أسباب الإرجاع',
        semantic: ReportTrendSemantic.warning,
        icon: Icons.undo_rounded,
      ));
    }

    if (exec.netCashFlow < 0) {
      insights.add(BusinessHealthInsight(
        title: 'ضغط على التدفق النقدي',
        message: 'صافي التدفق سالب — راجع المدفوعات والتحصيلات',
        semantic: ReportTrendSemantic.negative,
        icon: Icons.account_balance_wallet_outlined,
      ));
    }

    if (categories != null && categories.length >= 3) {
      final weak = categories.where((c) => c.contributionPercent < 3).take(2).toList();
      if (weak.isNotEmpty) {
        insights.add(BusinessHealthInsight(
          title: 'تصنيفات ضعيفة',
          message: 'مساهمة منخفضة: ${weak.map((c) => c.name).join('، ')}',
          semantic: ReportTrendSemantic.warning,
          icon: Icons.category_outlined,
        ));
      }
    }

    final deadCount = velocity?.slowMoving.where((r) => r.isDeadStock).length ?? 0;
    if (deadCount > 0) {
      insights.add(BusinessHealthInsight(
        title: 'تنبيه مخزون راكد',
        message: '$deadCount منتج(ات) بدون حركة بمخزون متبقٍ',
        semantic: ReportTrendSemantic.warning,
        icon: Icons.inventory_2_outlined,
      ));
    }

    if (employees != null && employees.length >= 2) {
      final avg = employees.fold<double>(0, (s, e) => s + e.salesAmount) / employees.length;
      final low = employees.where((e) => e.salesAmount < avg * 0.5).take(2).toList();
      if (low.isNotEmpty && avg > 0) {
        insights.add(BusinessHealthInsight(
          title: 'أداء كاشير منخفض',
          message: 'مبيعات أقل من المتوسط: ${low.map((e) => e.name).join('، ')}',
          semantic: ReportTrendSemantic.neutral,
          icon: Icons.badge_outlined,
        ));
      }
    }

    if (exec.receivableDebts > exec.payableDebts * 1.5 && exec.receivableDebts > 0) {
      insights.add(BusinessHealthInsight(
        title: 'ذمم مدينة مرتفعة',
        message: 'الذمم المدينة (${exec.receivableDebts.toStringAsFixed(0)}) تتجاوز الدائنة بشكل ملحوظ',
        semantic: ReportTrendSemantic.warning,
        icon: Icons.account_balance_rounded,
      ));
    }

    if (insights.isEmpty) {
      insights.add(const BusinessHealthInsight(
        title: 'الوضع مستقر',
        message: 'لا توجد مؤشرات خطرة في الفترة الحالية',
        semantic: ReportTrendSemantic.positive,
        icon: Icons.check_circle_outline_rounded,
      ));
    }

    return insights;
  }
}
