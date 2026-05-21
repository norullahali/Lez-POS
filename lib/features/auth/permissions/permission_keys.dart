// lib/features/auth/permissions/permission_keys.dart
class PermissionKeys {
  PermissionKeys._();

  static const posSell = 'pos.sell';
  static const posDiscount = 'pos.discount';
  static const posRefund = 'pos.refund';
  static const posFullRefund = 'pos.full_refund';

  static const productsView = 'products.view';
  static const productsEdit = 'products.edit';

  static const purchasesView = 'purchases.view';
  static const purchasesEdit = 'purchases.edit';

  static const reportsView = 'reports.view';

  static const settingsEdit = 'settings.edit';
  static const backupDatabase = 'backup_database';

  static const usersManage = 'users.manage';

  static const auditView = 'audit.view';
  static const auditExport = 'audit.export';
  static const securityView = 'security.view';

  static const all = [
    posSell,
    posDiscount,
    posRefund,
    posFullRefund,
    productsView,
    productsEdit,
    purchasesView,
    purchasesEdit,
    reportsView,
    settingsEdit,
    backupDatabase,
    usersManage,
    auditView,
    auditExport,
    securityView,
  ];

  static const descriptions = <String, String>{
    posSell: 'تشغيل نقطة البيع وتمشية الفواتير',
    posDiscount: 'إضافة خصومات على الفواتير',
    posRefund: 'إجراء مرتجعات (ضمن الحدود)',
    posFullRefund: 'إرجاع فاتورة كاملة',
    productsView: 'عرض قائمة المنتجات',
    productsEdit: 'إضافة وتعديل المنتجات والأقسام',
    purchasesView: 'عرض وإدارة المشتريات والموردين',
    purchasesEdit: 'تعديل المشتريات ومرتجعات الموردين',
    reportsView: 'الاطلاع على التقارير المالية',
    settingsEdit: 'تغيير إعدادات النظام',
    backupDatabase: 'إنشاء واستعادة النسخ الاحتياطية',
    usersManage: 'إدارة المستخدمين والصلاحيات',
    auditView: 'عرض سجل النشاط والتدقيق',
    auditExport: 'تصدير سجل النشاط',
    securityView: 'عرض أحداث الأمان',
  };

  static String descriptionFor(String key) => descriptions[key] ?? key;
}