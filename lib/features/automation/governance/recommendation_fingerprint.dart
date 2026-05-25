import '../models/automation_audit_context.dart';
import '../models/smart_action_item.dart';

class RecommendationFingerprint {
  RecommendationFingerprint._();

  static String forAction(SmartActionItem action) {
    if (action.fingerprint != null && action.fingerprint!.isNotEmpty) {
      return action.fingerprint!;
    }
    final entity = action.entityId != null ? '|${action.entityType}:${action.entityId}' : '';
    return '${action.category.name}|${action.id}$entity';
  }

  static String forKind({
    required AutomationSourceEngine engine,
    required String kind,
    String? entityType,
    int? entityId,
  }) {
    final entity = entityId != null ? '|$entityType:$entityId' : '';
    return '${engine.name}|$kind$entity';
  }
}