import '../cache/operations_cache.dart';

class OperationalEvaluationCache {
  OperationalEvaluationCache._();

  static const _prefix = 'ops_eval_';

  static Future<T> memo<T>(String key, Future<T> Function() loader) async {
    final cacheKey = '$_prefix$key';
    final cached = OperationsCache.get<T>(cacheKey);
    if (cached != null) return cached;
    final value = await loader();
    OperationsCache.set(cacheKey, value as Object);
    return value;
  }

  static void clear() => OperationsCache.invalidatePrefix(_prefix);
}