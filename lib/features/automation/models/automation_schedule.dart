enum AutomationScheduleFrequency { startup, daily, weekly, monthly }

class AutomationScheduleEntry {
  const AutomationScheduleEntry({
    required this.id,
    required this.labelAr,
    required this.frequency,
    required this.jobId,
    this.enabled = true,
  });
  final String id;
  final String labelAr;
  final AutomationScheduleFrequency frequency;
  final String jobId;
  final bool enabled;
}