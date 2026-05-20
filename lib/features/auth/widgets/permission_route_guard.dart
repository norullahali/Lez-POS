// lib/features/auth/widgets/permission_route_guard.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../permissions/route_permissions.dart';
import '../providers/permission_provider.dart';
import '../screens/unauthorized_screen.dart';

class PermissionRouteGuard extends ConsumerWidget {
  const PermissionRouteGuard({super.key, required this.child, this.permission, this.route});
  final Widget child;
  final String? permission;
  final String? route;

  factory PermissionRouteGuard.forRoute({Key? key, required String route, required Widget child}) {
    return PermissionRouteGuard(
      key: key,
      route: route,
      permission: permissionForRoute(route),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final required = permission ?? (route != null ? permissionForRoute(route!) : null);
    if (required == null) return child;
    final allowed = ref.watch(permissionProvider(required));
    if (allowed) return child;
    return UnauthorizedScreen(attemptedRoute: route);
  }
}