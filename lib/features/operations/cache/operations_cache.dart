class OperationsCache {
  OperationsCache._();

  static const defaultTtl = Duration(minutes: 3);
  static final Map<String, _Entry> _store = {};

  static T? get<T>(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return entry.value as T;
  }

  static void set(String key, Object value, {Duration? ttl}) {
    _store[key] = _Entry(value, DateTime.now().add(ttl ?? defaultTtl));
  }

  static void invalidatePrefix(String prefix) {
    _store.removeWhere((k, _) => k.startsWith(prefix));
  }

  static void clear() => _store.clear();
}

class _Entry {
  _Entry(this.value, this.expiresAt);
  final Object value;
  final DateTime expiresAt;
}
