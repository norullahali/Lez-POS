// lib/features/auth/providers/permission_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/permission_service.dart';
import 'auth_provider.dart';

final permissionServiceProvider = Provider<PermissionService>((ref) {
  final auth = ref.watch(authProvider).valueOrNull;
  return PermissionService.fromAuthState(auth);
});

final currentPermissionsProvider = Provider<List<String>>((ref) {
  return ref.watch(authProvider).valueOrNull?.permissions ?? const [];
});

final currentRoleIdProvider = Provider<int?>((ref) {
  return ref.watch(authProvider).valueOrNull?.user?.roleId;
});

final isSuperAdminProvider = Provider<bool>((ref) {
  return ref.watch(permissionServiceProvider).isSuperAdmin;
});

final permissionProvider = Provider.family<bool, String>((ref, key) {
  return ref.watch(permissionServiceProvider).hasPermissionSync(key);
});

final hasAnyPermissionProvider = Provider.family<bool, List<String>>((ref, keys) {
  return ref.watch(permissionServiceProvider).hasAny(keys);
});

final hasAllPermissionsProvider = Provider.family<bool, List<String>>((ref, keys) {
  return ref.watch(permissionServiceProvider).hasAll(keys);
});