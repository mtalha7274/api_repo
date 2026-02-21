### api_repo

A tiny repository mixin for Flutter/Dart that unifies **caching, retries, rate‑limiting, auto‑refresh, and logging** for any async request. Works with any HTTP client.

---

### Install

```bash
flutter pub add api_repo
```

---

### Quick start

```dart
class TodoApi with ApiRepo {
  Future<Map<String, dynamic>?> fetchTodo() async {
    return await onRequest<Map<String, dynamic>>(
      cachePolicy: CachePolicy.cacheFirst,
      ttl: const Duration(hours: 1),
      request: () async {
        final response = await Dio().get('https://jsonplaceholder.typicode.com/todos/1');
        return Map<String, dynamic>.from(response.data as Map);
      },
      onError: (e, st) => print('Error: $e'),
    );
  }
}
```

**One-time result** — just `await` it:

```dart
final todo = await TodoApi().fetchTodo();
```

**Continuous listening** — provide `onData` (e.g. with auto-refresh):

```dart
onRequest<Map<String, dynamic>>(
  autoRefreshInterval: const Duration(seconds: 30),
  cachePolicy: CachePolicy.cacheThenNetwork,
  request: () => fetchFromApi(),
  onData: (data, origin) => updateUI(data),
  onError: (error, stackTrace) => showError(error),
);
```

---

### API

```dart
Future<T?> onRequest<T>({
  String? key,
  Duration? autoRefreshInterval,
  required FutureOr<T> Function() request,
  void Function(T data, ResponseOrigin origin)? onData,
  void Function(Object error, StackTrace stackTrace)? onError,
  Duration? ttl,
  int? maxRetries,
  Duration? retryDelay,
  int? rateLimitPerSecond,
  CachePolicy? cachePolicy,
  bool? showLogs,
  LocalStorageManager? storageManager,
});
```

| Parameter | Description |
|---|---|
| `request` | The async function to execute (required) |
| `onData` | Called for every data delivery (cache hit, network, auto-refresh). Optional — omit to use the returned `Future<T?>` instead |
| `onError` | Called with error + `StackTrace` on any failure |
| `key` | Cache key. Auto-inferred from caller function name if omitted |
| `cachePolicy` | Cache strategy (see below) |
| `ttl` | Cache expiration duration |
| `autoRefreshInterval` | Re-fetch interval for background refresh |
| `maxRetries` / `retryDelay` | Retry count and linear backoff delay |
| `rateLimitPerSecond` | Max calls per second per key |
| `showLogs` | Print timing info for cache/network |
| `storageManager` | Custom `LocalStorageManager` for this call |

### Cache policies

| Policy | Behavior |
|---|---|
| `cacheOnly` | Return cached data; never hit network |
| `networkOnly` | Always hit network; ignore cache |
| `cacheFirst` | Return cache if present; otherwise fetch |
| `networkFirst` | Try network; fall back to cache on failure |
| `cacheThenNetwork` | Return cache immediately, then deliver network update when ready |

---

### Custom storage

Implement `LocalStorageManager` to use your own persistence:

```dart
class MyStorageManager implements LocalStorageManager {
  @override
  FutureOr<String?> getString({required String key}) {}
  @override
  Future<void> setString({required String key, required String value}) async {}
  @override
  Future<void> delete({required String key}) async {}
  @override
  Future<void> deleteAll() async {}
}

class MyRepo with ApiRepo {
  MyRepo() {
    defaultStorageManager = MyStorageManager();
  }
}
```

---

### Global defaults

```dart
class MyRepo with ApiRepo {
  MyRepo() {
    defaultCachePolicy = CachePolicy.cacheThenNetwork;
    defaultTtl = const Duration(minutes: 30);
    defaultAutoRefreshInterval = null;
    defaultShowLogs = kDebugMode;
    maxRetries = 2;
    retryDelay = const Duration(seconds: 1);
    rateLimitPerSecond = 5;
  }
}
```

Override any default per call via `onRequest<T>()` parameters.

---

### License

MIT — see `LICENSE` for details.
