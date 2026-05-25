enum OperationalAlertType {
  lowStock,
  deadStock,
  suspiciousRefund,
  highReturnRate,
  cashierAnomaly,
  overdueDebt,
  inventoryMismatch,
  weakSales,
  unusualActivity,
  sessionMismatch,
  expiryNear,
  expiryCritical,
  overstockRisk,
  lowStockPrediction,
}

extension OperationalAlertTypeX on OperationalAlertType {
  String get labelAr => switch (this) {
        OperationalAlertType.lowStock => 'مخزون منخفض',
        OperationalAlertType.deadStock => 'مخزون راكد',
        OperationalAlertType.suspiciousRefund => 'مرتجعات مشبوهة',
        OperationalAlertType.highReturnRate => 'ارتفاع المرتجعات',
        OperationalAlertType.cashierAnomaly => 'سلوك كاشير غير اعتيادي',
        OperationalAlertType.overdueDebt => 'ذمم متأخرة',
        OperationalAlertType.inventoryMismatch => 'فرق مخزون',
        OperationalAlertType.weakSales => 'مبيعات ضعيفة',
        OperationalAlertType.unusualActivity => 'نشاط غير اعتيادي',
        OperationalAlertType.sessionMismatch => 'فرق جلسة',
        OperationalAlertType.expiryNear => 'قرب انتهاء الصلاحية',
        OperationalAlertType.expiryCritical => 'صلاحية حرجة',
        OperationalAlertType.overstockRisk => 'خطر تكدس',
        OperationalAlertType.lowStockPrediction => 'تنبؤ نفاد مخزون',
      };
}
