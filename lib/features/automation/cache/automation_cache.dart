class AutomationCache {
  AutomationCache._();
  static const defaultTtl = Duration(minutes: 5);
  static final Map<String, _Entry> _store = {};
  static final Map<String, Future<Object?>> _inFlight = {};

  static T? get<T>(String key) {
    final e = _store[key];
    if (e == null || DateTime.now().isAfter(e.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return e.value as T;
  }

  static void set(String key, Object value, {Duration? ttl}) {
    _store[key] = _Entry(value, DateTime.now().add(ttl ?? defaultTtl));
  }

  static Future<T> memo<T>(String key, Future<T> Function() loader, {Duration? ttl}) async {
    final cached = get<T>(key);
    if (cached != null) return cached;

    final pending = _inFlight[key];
    if (pending != null) return await pending as T;

    final future = loader().then((value) {
      set(key, value as Object, ttl: ttl);
      _inFlight.remove(key);
      return value;
    });
    _inFlight[key] = future;
    return future;
  }

  static void invalidatePrefix(String prefix) {
    _store.removeWhere((k, _) => k.startsWith(prefix));
    _inFlight.removeWhere((k, _) => k.startsWith(prefix));
  }

  static void clear() {
    _store.clear();
    _inFlight.clear();
  }
}

class _Entry {
  _Entry(this.value, this.expiresAt);
  final Object value;
  final DateTime expiresAt;
}
