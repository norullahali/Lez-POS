import 'package:flutter/material.dart';

import 'advanced_analytics_models.dart';

enum VelocityClass {
  fast('سريع', Colors.green),
  normal('عادي', Colors.blue),
  slow('بطيء', Colors.orange),
  deadStock('مخزون راكد', Colors.red);

  const VelocityClass(this.labelAr, this.color);
  final String labelAr;
  final Color color;
}

class VelocityClassifier {
  VelocityClassifier._();

  static VelocityClass classify(VelocityRow row, {required bool fromSlowList}) {
    if (row.isDeadStock || (fromSlowList && row.quantity == 0 && row.value > 0)) {
      return VelocityClass.deadStock;
    }
    if (!fromSlowList && row.quantity >= 15) return VelocityClass.fast;
    if (fromSlowList && row.quantity <= 1) return VelocityClass.slow;
    return VelocityClass.normal;
  }

  static double turnoverEstimate(double soldQty, double stockOnHand) {
    if (stockOnHand <= 0) return soldQty;
    return soldQty / stockOnHand;
  }

  static String turnoverLabel(double ratio) {
    if (ratio >= 1.5) return 'دوران مرتفع';
    if (ratio >= 0.5) return 'دوران طبيعي';
    if (ratio > 0) return 'دوران منخفض';
    return 'بدون حركة';
  }
}