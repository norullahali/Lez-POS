// lib/features/auth/permissions/system_roles.dart
//
// Stable internal keys for built-in system roles (DB-backed via roles.system_key).
class SystemRoles {
  SystemRoles._();

  /// Stable internal identity for the owner role.
  static const String ownerKey = 'owner';

  /// Localized display name (UI / legacy seed data only).
  static const String ownerDisplayName = 'المالك';

  /// @deprecated Use [ownerDisplayName] for UI labels.
  static const String ownerRoleName = ownerDisplayName;
}