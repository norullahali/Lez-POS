enum ExpiryAlertLevel { expired, critical, warning, none }

class ExpiryAlertItem {
  const ExpiryAlertItem({
    required this.productId,
    required this.productName,
    required this.expiryDate,
    required this.level,
    this.batchId,
  });

  final int productId;
  final String productName;
  final DateTime expiryDate;
  final ExpiryAlertLevel level;
  final int? batchId;
}

class ExpiryMonitoringSnapshot {
  const ExpiryMonitoringSnapshot({
    required this.trackingEnabled,
    required this.items,
  });

  final bool trackingEnabled;
  final List<ExpiryAlertItem> items;

  static const empty = ExpiryMonitoringSnapshot(trackingEnabled: false, items: []);
}
