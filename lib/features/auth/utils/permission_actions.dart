// lib/features/auth/utils/permission_actions.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/permission_provider.dart';

class PermissionActions {
  PermissionActions._();
  static const deniedMessage = 'ليس لديك صلاحية لتنفيذ هذه العملية';

  static bool guard(WidgetRef ref, BuildContext context, String permission) {
    final allowed = ref.read(permissionServiceProvider).hasPermissionSync(permission);
    if (allowed) return true;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text(deniedMessage)),
    );
    return false;
  }

  static Future<bool> guardAsync(WidgetRef ref, BuildContext context, String permission) async {
    final allowed = await ref.read(permissionServiceProvider).hasPermission(permission);
    if (allowed) return true;
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(deniedMessage)),
      );
    }
    return false;
  }
}