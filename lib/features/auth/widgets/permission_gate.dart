// lib/features/auth/widgets/permission_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/permission_provider.dart';
import '../utils/permission_actions.dart';

class PermissionGate extends ConsumerWidget {
  const PermissionGate({super.key, required this.permission, required this.child, this.fallback});
  final String permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(permissionProvider(permission));
    if (allowed) return child;
    return fallback ?? const SizedBox.shrink();
  }
}

class PermissionVisibility extends ConsumerWidget {
  const PermissionVisibility({super.key, required this.permission, required this.child, this.fallback});
  final String permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PermissionGate(permission: permission, fallback: fallback, child: child);
  }
}

class PermissionDisable extends ConsumerWidget {
  const PermissionDisable({super.key, required this.permission, required this.child, this.denialMessage = PermissionActions.deniedMessage});
  final String permission;
  final Widget child;
  final String denialMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(permissionProvider(permission));
    return Tooltip(
      message: allowed ? '' : denialMessage,
      child: Opacity(
        opacity: allowed ? 1 : 0.45,
        child: AbsorbPointer(absorbing: !allowed, child: child),
      ),
    );
  }
}