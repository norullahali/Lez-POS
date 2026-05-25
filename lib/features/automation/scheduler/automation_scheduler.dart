import '../models/automation_schedule.dart';

class AutomationScheduler {
  AutomationScheduler._();

  static const entries = [
    AutomationScheduleEntry(
      id: 'sched_daily_refresh',
      labelAr: 'تحديث التوصيات اليومية',
      frequency: AutomationScheduleFrequency.daily,
      jobId: 'automation_daily_refresh',
    ),
    AutomationScheduleEntry(
      id: 'sched_weekly_review',
      labelAr: 'مراجعة تشغيلية أسبوعية',
      frequency: AutomationScheduleFrequency.weekly,
      jobId: 'automation_weekly_review',
    ),
    AutomationScheduleEntry(
      id: 'sched_startup',
      labelAr: 'تهيئة الأتمتة عند التشغيل',
      frequency: AutomationScheduleFrequency.startup,
      jobId: 'automation_startup',
    ),
    AutomationScheduleEntry(
      id: 'sched_reorder',
      labelAr: 'توليد اقتراحات إعادة الطلب',
      frequency: AutomationScheduleFrequency.daily,
      jobId: 'automation_reorder',
    ),
    AutomationScheduleEntry(
      id: 'sched_debt',
      labelAr: 'تحليل الذمم',
      frequency: AutomationScheduleFrequency.daily,
      jobId: 'automation_debt',
    ),
    AutomationScheduleEntry(
      id: 'sched_loyalty',
      labelAr: 'تحديث ولاء العملاء',
      frequency: AutomationScheduleFrequency.weekly,
      jobId: 'automation_loyalty',
    ),
  ];
}