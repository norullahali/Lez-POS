// lib/features/auth/permissions/route_permissions.dart
//
// Maps application routes to required permission keys.
import 'permission_keys.dart';

/// Returns the permission required for [location], or null if any
/// authenticated user may access the route.
String? permissionForRoute(String location) {
  final normalized = location.split('?').first;

  for (final entry in _routePermissionEntries) {
    if (normalized == entry.route) return entry.permission;
  }

  for (final entry in _routePermissionEntries) {
    if (entry.route != '/' &&
        normalized.startsWith('${entry.route}/')) {
      return entry.permission;
    }
  }

  return null;
}

class _RoutePermission {
  final String route;
  final String? permission;
  const _RoutePermission(this.route, this.permission);
}

const _routePermissionEntries = [
  _RoutePermission('/', null),
  _RoutePermission('/dashboard', null),
  _RoutePermission('/login', null),
  _RoutePermission('/unauthorized', null),
  _RoutePermission('/pos', PermissionKeys.posSell),
  _RoutePermission('/products', PermissionKeys.productsView),
  _RoutePermission('/categories', PermissionKeys.productsView),
  _RoutePermission('/customers', PermissionKeys.posSell),
  _RoutePermission('/suppliers', PermissionKeys.purchasesView),
  _RoutePermission('/purchases', PermissionKeys.purchasesView),
  _RoutePermission('/opening-stock', PermissionKeys.productsEdit),
  _RoutePermission('/inventory', PermissionKeys.productsView),
  _RoutePermission('/customer-returns', PermissionKeys.posRefund),
  _RoutePermission('/supplier-returns', PermissionKeys.purchasesEdit),
  _RoutePermission('/reports', PermissionKeys.reportsView),
  _RoutePermission('/return-analytics', PermissionKeys.reportsView),
  _RoutePermission('/invoice-history', PermissionKeys.reportsView),
  _RoutePermission('/users', PermissionKeys.usersManage),
  _RoutePermission('/roles', PermissionKeys.usersManage),
  _RoutePermission('/backup', PermissionKeys.settingsEdit),
  _RoutePermission('/pricing', PermissionKeys.settingsEdit),
  _RoutePermission('/loyalty-settings', PermissionKeys.settingsEdit),
  _RoutePermission('/settings', PermissionKeys.settingsEdit),
  _RoutePermission('/settings/invoice', PermissionKeys.settingsEdit),
];
