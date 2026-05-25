enum ScheduledReportFrequency { daily, weekly, monthly }

class ScheduledReportConfig {
  const ScheduledReportConfig({
    required this.id,
    required this.titleAr,
    required this.frequency,
    required this.enabled,
    this.lastGeneratedAt,
    this.lastFilePath,
  });

  final String id;
  final String titleAr;
  final ScheduledReportFrequency frequency;
  final bool enabled;
  final DateTime? lastGeneratedAt;
  final String? lastFilePath;

  ScheduledReportConfig copyWith({
    bool? enabled,
    DateTime? lastGeneratedAt,
    String? lastFilePath,
  }) {
    return ScheduledReportConfig(
      id: id,
      titleAr: titleAr,
      frequency: frequency,
      enabled: enabled ?? this.enabled,
      lastGeneratedAt: lastGeneratedAt ?? this.lastGeneratedAt,
      lastFilePath: lastFilePath ?? this.lastFilePath,
    );
  }
}
