// lib/core/activity/activity_context.dart
class ActivityContextSnapshot {
  const ActivityContextSnapshot({
    this.userId,
    this.username,
    this.roleName,
    this.sessionId,
    this.routeContext,
  });

  final int? userId;
  final String? username;
  final String? roleName;
  final int? sessionId;
  final String? routeContext;

  static const empty = ActivityContextSnapshot();

  ActivityContextSnapshot copyWith({
    int? userId,
    String? username,
    String? roleName,
    int? sessionId,
    String? routeContext,
  }) {
    return ActivityContextSnapshot(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      roleName: roleName ?? this.roleName,
      sessionId: sessionId ?? this.sessionId,
      routeContext: routeContext ?? this.routeContext,
    );
  }
}

class ActivityContextHolder {
  ActivityContextHolder._();

  static ActivityContextSnapshot current = ActivityContextSnapshot.empty;

  static void update(ActivityContextSnapshot snapshot) {
    current = snapshot;
  }

  static void clear() {
    current = ActivityContextSnapshot.empty;
  }
}