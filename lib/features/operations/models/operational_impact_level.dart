enum OperationalImpactLevel {
  low,
  medium,
  high,
  critical;

  String get labelAr => switch (this) {
        OperationalImpactLevel.low => 'منخفض',
        OperationalImpactLevel.medium => 'متوسط',
        OperationalImpactLevel.high => 'مرتفع',
        OperationalImpactLevel.critical => 'حرج',
      };

  int get sortOrder => switch (this) {
        OperationalImpactLevel.critical => 0,
        OperationalImpactLevel.high => 1,
        OperationalImpactLevel.medium => 2,
        OperationalImpactLevel.low => 3,
      };
}