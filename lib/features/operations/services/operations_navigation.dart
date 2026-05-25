import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OperationsNavigation {
  OperationsNavigation._();

  static const _safeRoutes = {
    '/inventory',
    '/reports',
    '/return-analytics',
    '/activity',
    '/activity/timeline',
    '/customers',
    '/operations/notifications',
    '/dashboard',
  };

  static bool isSafeRoute(String? route) {
    if (route == null || route.isEmpty) return false;
    if (_safeRoutes.contains(route)) return true;
    if (route.startsWith('/customers/profile/')) {
      final id = route.split('/').last;
      return int.tryParse(id) != null;
    }
    return false;
  }

  static String fallbackRoute(String? route) {
    if (isSafeRoute(route)) return route!;
    return '/dashboard';
  }

  static void navigate(BuildContext context, String? route) {
    final target = fallbackRoute(route);
    if (context.canPop() && target.startsWith('/customers/profile')) {
      context.push(target);
      return;
    }
    context.go(target);
  }
}