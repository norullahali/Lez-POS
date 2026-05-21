import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/app_database.dart';
import '../../../core/activity/activity_categories.dart';
import '../../../core/activity/activity_context.dart';
import '../../../core/activity/activity_types.dart';
import '../../../core/services/activity_logger_service.dart';
import '../permissions/permission_rules.dart';
import '../permissions/role_identity.dart';

class AuthState {
  final User? user;
  final List<String> permissions;

  const AuthState({this.user, this.permissions = const []});

  bool get isAuthenticated => user != null;
  
  bool hasPermission(String key) {
    return PermissionRules.hasPermission(
      roleId: user?.roleId,
      permissions: permissions,
      key: key,
    );
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthState> {
  late AppDatabase _db;

  @override
  FutureOr<AuthState> build() async {
    try {
      _db = AppDatabase.instance;
      debugPrint('[AuthNotifier] build: initialized.');
      return const AuthState(); // Not logged in initially
    } catch (e, st) {
      debugPrint('[AuthNotifier] build error: $e\n$st');
      rethrow;
    }
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    final logger = ActivityLoggerService(_db);
    state = await AsyncValue.guard(() async {
      debugPrint('[AuthNotifier] login: attempting for user "$username"...');
      final user = await _db.usersDao.getUserByUsername(username);
      if (user == null || !user.isActive) {
        debugPrint('[AuthNotifier] login: user not found or inactive.');
        await logger.logWarning(
          activityType: ActivityTypes.loginFailed,
          category: ActivityCategories.auth,
          action: 'login',
          title: 'فشل تسجيل الدخول',
          description: 'مستخدم غير موجود أو غير مفعّل',
          contextOverride: ActivityContextSnapshot(username: username),
        );
        throw Exception('المستخدم غير موجود أو غير مفعل');
      }

      final hashedPassword = sha256.convert(utf8.encode(password)).toString();
      debugPrint('[AuthNotifier] login: checking password hash...');
      if (user.passwordHash != hashedPassword) {
        debugPrint('[AuthNotifier] login: incorrect password. stored=${user.passwordHash}, provided=$hashedPassword');
        await logger.logWarning(
          activityType: ActivityTypes.loginFailed,
          category: ActivityCategories.auth,
          action: 'login',
          title: 'فشل تسجيل الدخول',
          description: 'كلمة مرور غير صحيحة',
          contextOverride: ActivityContextSnapshot(username: username),
        );
        throw Exception('كلمة المرور غير صحيحة');
      }

      debugPrint('[AuthNotifier] login: success for user "${user.username}" (role=${user.roleId}).');
      // Fetch user's permissions
      final perms = await _db.usersDao.getRolePermissionsKeys(user.roleId);
      debugPrint('[AuthNotifier] login: permissions loaded: $perms');

      String? roleName;
      try {
        final role = await _db.usersDao.getRoleById(user.roleId);
        roleName = role?.roleName;
      } catch (_) {}
      ActivityContextHolder.update(ActivityContextSnapshot(
        userId: user.id,
        username: user.username,
        roleName: roleName,
      ));
      await logger.logInfo(
        activityType: ActivityTypes.loginSuccess,
        category: ActivityCategories.auth,
        action: 'login',
        title: 'تسجيل دخول ناجح',
        description: user.username,
        entityType: 'user',
        entityId: user.id,
      );

      return AuthState(user: user, permissions: perms);
    });

    if (state is AsyncError) {
      debugPrint('[AuthNotifier] login: final state is error: ${state.error}');
    }
  }

  void logout() {
    debugPrint('[AuthNotifier] logout.');
    final user = state.valueOrNull?.user;
    if (user != null) {
      ActivityLoggerService(_db).logInfo(
        activityType: ActivityTypes.logout,
        category: ActivityCategories.auth,
        action: 'logout',
        title: 'تسجيل خروج',
        description: user.username,
        entityType: 'user',
        entityId: user.id,
      );
    }
    state = const AsyncData(AuthState());
  }

  /// Specialized method for quick, in-flight validation of manager PINs
  /// Returns the User if valid and they possess the [requiredPermission].
  Future<User?> validatePinForPermission(String pin, String requiredPermission) async {
    final user = await _db.usersDao.getUserByPin(pin);
    if (user == null || !user.isActive) return null;
    
    // Check their permissions via role
    if (RoleIdentity.isOwnerRole(user.roleId)) return user;
    
    final perms = await _db.usersDao.getRolePermissionsKeys(user.roleId);
    if (perms.contains(requiredPermission)) {
      return user;
    }
    return null;
  }
}
