// lib/features/activity/providers/activity_context_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/activity/activity_context.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/activity_logger_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pos/providers/pos_provider.dart';

final activityLoggerProvider = Provider<ActivityLoggerService>((ref) {
  ref.watch(activityContextSyncProvider);
  return ActivityLoggerService(AppDatabase.instance);
});

final activityContextSyncProvider = Provider<void>((ref) {
  ref.listen(authProvider, (_, next) async {
    final auth = next.valueOrNull;
    if (auth?.user == null) {
      ActivityContextHolder.clear();
      return;
    }
    final user = auth!.user!;
    String? roleName;
    try {
      final role = await AppDatabase.instance.usersDao.getRoleById(user.roleId);
      roleName = role?.roleName;
    } catch (_) {}
    final sessionId = ref.read(posSessionProvider).valueOrNull?.id;
    ActivityContextHolder.update(ActivityContextSnapshot(
      userId: user.id,
      username: user.username,
      roleName: roleName,
      sessionId: sessionId,
    ));
  }, fireImmediately: true);

  ref.listen(posSessionProvider, (_, next) {
    ActivityContextHolder.update(
      ActivityContextHolder.current.copyWith(sessionId: next.valueOrNull?.id),
    );
  });
});