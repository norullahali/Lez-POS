/// Lightweight in-memory cache for report queries.
/// Invalidated on filter changes; never persists to disk.
class ReportQueryCache {
  ReportQueryCache._();

  static final _store = <String, _CacheEntry>{};
  static const Duration defaultTtl = Duration(minutes: 2);

  static T? get<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return entry.data as T?;
  }

  static void set(String key, Object data, {Duration ttl = defaultTtl}) {
    _store[key] = _CacheEntry(
      data: data,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  static void invalidate(String key) => _store.remove(key);

  static void invalidatePrefix(String prefix) {
    _store.removeWhere((key, _) => key.startsWith(prefix));
  }

  static void clear() => _store.clear();
}

class _CacheEntry {
  _CacheEntry({required this.data, required this.expiresAt});
  final Object data;
  final DateTime expiresAt;
}