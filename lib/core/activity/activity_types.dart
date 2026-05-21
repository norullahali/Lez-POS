// lib/core/activity/activity_types.dart
class ActivityTypes {
  ActivityTypes._();

  static const loginSuccess = 'auth.login.success';
  static const loginFailed = 'auth.login.failed';
  static const logout = 'auth.logout';

  static const invoiceCreated = 'sales.invoice.created';
  static const invoiceReprinted = 'sales.invoice.reprinted';

  static const returnFull = 'returns.full';
  static const returnPartial = 'returns.partial';
  static const returnSmartLookup = 'returns.smart_lookup';

  static const stockAdjusted = 'inventory.stock.adjusted';
  static const productCreated = 'inventory.product.created';
  static const productUpdated = 'inventory.product.updated';
  static const productToggled = 'inventory.product.toggled';

  static const userCreated = 'users.user.created';
  static const userUpdated = 'users.user.updated';
  static const roleUpdated = 'users.role.updated';

  static const settingsUpdated = 'settings.updated';
  static const backupCreated = 'backup.created';
  static const backupRestoreStarted = 'backup.restore.started';

  static const sessionOpened = 'sessions.opened';
  static const sessionClosed = 'sessions.closed';
}