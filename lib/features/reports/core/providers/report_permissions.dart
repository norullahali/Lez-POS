import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/permissions/permission_keys.dart';
import '../../../auth/providers/permission_provider.dart';

final canViewReportsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.reportsView));
});

final canExportReportsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.reportsExport));
});

final canViewAnalyticsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.analyticsView));
});

final canViewExecutiveAnalyticsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.analyticsExecutive));
});

final canViewFinancialAnalyticsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.analyticsFinancial));
});

final canViewInventoryAnalyticsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.analyticsInventory));
});

final canViewProductsForReportsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.productsView));
});

final canViewPurchasesForReportsProvider = Provider<bool>((ref) {
  return ref.watch(permissionProvider(PermissionKeys.purchasesView));
});
