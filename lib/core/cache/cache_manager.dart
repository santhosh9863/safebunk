typedef CacheClearCallback = void Function();
typedef AsyncCacheClearCallback = Future<void> Function();

class CacheManager {
  final List<CacheClearCallback> _syncCallbacks = [];
  final List<AsyncCacheClearCallback> _asyncCallbacks = [];

  void register(CacheClearCallback callback) {
    _syncCallbacks.add(callback);
  }

  void registerAsync(AsyncCacheClearCallback callback) {
    _asyncCallbacks.add(callback);
  }

  Future<void> clearAll() async {
    for (final callback in _syncCallbacks) {
      callback();
    }
    for (final callback in _asyncCallbacks) {
      await callback();
    }
  }
}
