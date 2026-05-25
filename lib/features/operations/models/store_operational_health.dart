enum StoreHealthStatus {
  excellent,
  healthy,
  warning,
  critical;

  String get labelAr => switch (this) {
        StoreHealthStatus.excellent => 'ممتاز',
        StoreHealthStatus.healthy => 'سليم',
        StoreHealthStatus.warning => 'تحذير',
        StoreHealthStatus.critical => 'حرج',
      };
}

class StoreOperationalHealth {
  const StoreOperationalHealth({
    required this.score,
    required this.status,
    required this.factors,
    required this.evaluatedAt,
  });

  final int score;
  final StoreHealthStatus status;
  final List<String> factors;
  final DateTime evaluatedAt;
}