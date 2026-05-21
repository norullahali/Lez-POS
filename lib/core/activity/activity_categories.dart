// lib/core/activity/activity_categories.dart
class ActivityCategories {
  ActivityCategories._();

  static const auth = 'auth';
  static const sales = 'sales';
  static const returns = 'returns';
  static const inventory = 'inventory';
  static const users = 'users';
  static const settings = 'settings';
  static const security = 'security';
  static const sessions = 'sessions';
  static const backup = 'backup';

  static const all = [
    auth,
    sales,
    returns,
    inventory,
    users,
    settings,
    security,
    sessions,
    backup,
  ];

  static String labelAr(String category) => switch (category) {
        auth => 'المصادقة',
        sales => 'المبيعات',
        returns => 'المرتجعات',
        inventory => 'المخزون',
        users => 'المستخدمون',
        settings => 'الإعدادات',
        security => 'الأمان',
        sessions => 'الجلسات',
        backup => 'النسخ الاحتياطي',
        _ => category,
      };
}