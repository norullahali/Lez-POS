import 'package:flutter/material.dart';

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

  static IconData iconFor(String category) => switch (category) {
        auth => Icons.shield_outlined,
        sales => Icons.point_of_sale_outlined,
        returns => Icons.undo_rounded,
        inventory => Icons.inventory_2_outlined,
        users => Icons.people_outline_rounded,
        settings => Icons.settings_outlined,
        security => Icons.security_rounded,
        sessions => Icons.schedule_rounded,
        backup => Icons.backup_outlined,
        _ => Icons.history_rounded,
      };
}