import '../models/operational_alert_state.dart';
import 'alert_lifecycle_store.dart';

class OperationsDismissStore {
  OperationsDismissStore._();

  static Future<Set<String>> loadDismissedIds() async {
    final records = await AlertLifecycleStore.loadRecords();
    return records.entries
        .where((e) =>
            e.value.state == OperationalAlertState.archived ||
            e.value.state == OperationalAlertState.resolved)
        .map((e) => e.key)
        .toSet();
  }

  static Future<void> dismiss(String alertId) => AlertLifecycleStore.dismiss(alertId);

  static Future<void> restore(String alertId) =>
      AlertLifecycleStore.transition(alertId, OperationalAlertState.active);

  static Future<void> clearAll() async {
    await AlertLifecycleStore.saveRecords({});
  }
}