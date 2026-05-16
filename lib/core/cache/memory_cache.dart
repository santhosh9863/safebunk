class MemoryCache<T> {
  final Duration ttl;
  final Map<String, _CacheEntry<T>> _entries = {};

  MemoryCache({required this.ttl});

  T? get(String key) {
    final entry = _entries[key];
    if (entry == null || entry.isExpired) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void set(String key, T value) {
    _entries[key] = _CacheEntry(value, ttl);
  }

  void invalidate(String key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;

  _CacheEntry(this.value, Duration ttl)
      : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
