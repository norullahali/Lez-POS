// lib/features/reports/core/models/report_date_preset.dart
enum ReportDatePreset {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  thisYear,
  custom,
}

extension ReportDatePresetX on ReportDatePreset {
  String get labelAr => switch (this) {
        ReportDatePreset.today => 'اليوم',
        ReportDatePreset.yesterday => 'أمس',
        ReportDatePreset.thisWeek => 'هذا الأسبوع',
        ReportDatePreset.thisMonth => 'هذا الشهر',
        ReportDatePreset.thisYear => 'هذه السنة',
        ReportDatePreset.custom => 'مخصص',
      };

  static List<ReportDatePreset> get rangePresets => [
        ReportDatePreset.today,
        ReportDatePreset.yesterday,
        ReportDatePreset.thisWeek,
        ReportDatePreset.thisMonth,
        ReportDatePreset.thisYear,
        ReportDatePreset.custom,
      ];
}