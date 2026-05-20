// lib/features/auth/permissions/permission_keys.dart
//
// Central registry of permission key strings used across the app.
class PermissionKeys {
  PermissionKeys._();

  // ---- POS ----
  static const posSell = 'pos.sell';
  static const posDiscount = 'pos.discount';
  static const posRefund = 'pos.refund';
  static const posFullRefund = 'pos.full_refund';

  // ---- Products & inventory ----
  static const productsView = 'products.view';
  static const productsEdit = 'products.edit';

  // ---- Purchases ----
  static const purchasesView = 'purchases.view';
  static const purchasesEdit = 'purchases.edit';

  // ---- Reports & analytics ----
  static const reportsView = 'reports.view';

  // ---- Settings & backup ----
  static const settingsEdit = 'settings.edit';
  static const backupDatabase = 'backup_database';

  // ---- Users & roles ----
  static const usersManage = 'users.manage';

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
  ];
}
