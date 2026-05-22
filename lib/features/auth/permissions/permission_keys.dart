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
  static const reportsExport = 'reports.export';
  static const analyticsView = 'analytics.view';
  static const analyticsExecutive = 'analytics.executive';
  static const analyticsFinancial = 'analytics.financial';
  static const analyticsInventory = 'analytics.inventory';

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
    reportsExport,
    analyticsView,
    analyticsExecutive,
    analyticsFinancial,
    analyticsInventory,
    settingsEdit,
    backupDatabase,
    usersManage,
    auditView,
    auditExport,
    securityView,
  ];

  static const descriptions = <String, String>{
    posSell: 'إجراء عمليات البيع من نقطة البيع',
    posDiscount: 'تطبيق خصم على الفواتير',
    posRefund: 'إجراء المرتجعات (جزئي أو كامل)',
    posFullRefund: 'إجراء استرجاع كامل',
    productsView: 'عرض قائمة المنتجات',
    productsEdit: 'إضافة وتعديل المنتجات والأسعار',
    purchasesView: 'عرض فواتير المشتريات والموردين',
    purchasesEdit: 'إضافة المشتريات وتعديل بيانات الموردين',
    reportsView: 'الاطلاع على التقارير والإحصائيات',
    reportsExport: 'تصدير التقارير إلى ملفات',
    analyticsView: 'عرض التحليلات المتقدمة',
    analyticsExecutive: 'عرض لوحة الإدارة التنفيذية',
    analyticsFinancial: 'عرض التحليلات المالية المتقدمة',
    analyticsInventory: 'عرض تحليلات المخزون المتقدمة',
    settingsEdit: 'تعديل إعدادات النظام',
    backupDatabase: 'أخذ نسخة احتياطية من قاعدة البيانات',
    usersManage: 'إدارة المستخدمين والصلاحيات',
    auditView: 'عرض سجل النشاط والتدقيق',
    auditExport: 'تصدير سجل النشاط',
    securityView: 'عرض إعدادات الأمان',
  };

  static String descriptionFor(String key) => descriptions[key] ?? key;
}