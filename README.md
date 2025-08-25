### api_repo

**A tiny repository mixin for Flutter/Dart that unifies caching, retries, rate‑limiting, auto‑refresh, and logging for any async request.**

Works with any HTTP client (Dio, http, GraphQL, gRPC, custom SDKs) and persists cache on disk via `SharedPreferences` by default. Bring your own storage by implementing a simple `LocalStorageManager` interface.

The core idea: write your domain repositories as usual, mix in `ApiRepo`, and call one method `onRequest<T>()` to get all the ergonomics (cache, retry, rate limiting, auto-refresh) with clear, typed callbacks and minimal boilerplate.

---

### Features

- **Unified request helper**: `onRequest<T>()` wraps any async function
- **Flexible cache strategies**: `cacheOnly`, `networkOnly`, `cacheFirst`, `networkFirst`, `cacheThenNetwork`
- **Disk cache with TTL**: persisted via `SharedPreferences` (or pluggable store)
- **Auto-refresh**: optionally re-fetch on an interval using a background timer
- **Retries with linear backoff**: configure attempts and delay per call or globally
- **Per-key rate limiting**: throttle calls per second per key
- **Structured logging**: opt‑in performance timing for cache and network
- **Sensible defaults with per-call overrides**: set global defaults once, override when needed
- **DI convenience**: simple `initializeDependencies()` using `get_it` and `shared_preferences`

---

### Install

In your terminal, run:

```bash
flutter pub add api_repo
```

---

### Getting started

1) Create your repository and mix in `ApiRepo`:

```dart
import 'package:api_repo/api_repo.dart';
import 'package:api_repo/data/managers/cache_policy.dart';
import 'package:dio/dio.dart'; // or any client you prefer
import 'package:flutter/foundation.dart';

class TodoApi with ApiRepo {
  TodoApi() {
    defaultShowLogs = true; // optional: enable logs globally for this repo
  }

  void fetchTodo({
    required void Function(Map<String, dynamic>? data, ResponseOrigin origin)
        onData,
  }) {
    onRequest<Map<String, dynamic>?>(
      cachePolicy: CachePolicy.cacheThenNetwork,
      ttl: const Duration(hours: 1),
      request: _fetchTodoApi,
      onData: onData,
    );
  }

  Future<Map<String, dynamic>?> _fetchTodoApi() async {
    try {
      final response = await Dio().get(
        'https://jsonplaceholder.typicode.com/todos/1',
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      debugPrint('Error: $e');
      return null;
    }
  }
}
```

2) Consume it from your UI:

```dart
class ApiRepoExample extends StatefulWidget {
  const ApiRepoExample({super.key});
  @override
  State<ApiRepoExample> createState() => _ApiRepoExampleState();
}

class _ApiRepoExampleState extends State<ApiRepoExample> {
  String _data = 'Loading...';
  final TodoApi _api = TodoApi();

  @override
  void initState() {
    super.initState();
    _api.fetchTodo(
      onData: (data, origin) {
        if (data == null) {
          setState(() => _data = 'Error: No data received');
          return;
        }
        setState(() => _data =
            'Title: ${data['title']}\n Completed: ${data['completed']}');
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('API Example')),
        body: Center(child: Text(_data)),
      );
}
```

You can see the complete, runnable example in `example/lib/main.dart`.

---

### How it works

Mix in `ApiRepo` to your repository class. Call `onRequest<T>()` to perform a read/fetch with built‑in cache, retry, rate limiting, auto‑refresh and logging. Delivery is via the `onData` callback with the typed data and a `ResponseOrigin` indicating whether it came from `cache` or `network`.

```dart
void onRequest<T>({
  String? key,
  Duration? autoRefreshInterval,
  required FutureOr<T> Function() request,
  required void Function(T data, ResponseOrigin origin) onData,
  Duration? ttl,
  int? maxRetries,
  Duration? retryDelay,
  int? rateLimitPerSecond,
  CachePolicy? cachePolicy,
  bool? showLogs,
});
```

- **Key**: if omitted, `ApiRepo` infers it from the caller function name. Provide one when calls originate from the same function but represent different resources.
- **Cache policy**: choose behavior for cache vs network (see below).
- **TTL**: when set, cached entries auto‑expire after the duration. If `null`, entries do not auto‑expire.
- **Retries**: configure attempts and delay; linear backoff is applied (1×, 2×, 3× delay ...).
- **Rate limiting**: limit calls per second per key. When exceeded, the request waits before firing.
- **Auto‑refresh**: pass an interval to re‑fetch periodically. Re‑scheduling the same key replaces the prior timer.
- **Logging**: enable to print timing info for cache and network operations.

`ResponseOrigin` values:

```dart
enum ResponseOrigin { cache, network }
```

Supported cache policies (`CachePolicy`):

- `cacheOnly`: return cached data; never hit network
- `networkOnly`: always hit network; ignore cache
- `cacheFirst`: return cache when present; otherwise hit network
- `networkFirst`: try network; fall back to cache on failure
- `cacheThenNetwork`: immediately return cache when present, then also deliver a network update when it completes

---

### Advanced configuration

Set global defaults on your repository (applied when a call doesn’t override them):

```dart
class MyRepo with ApiRepo {
  MyRepo() {
    defaultCachePolicy = CachePolicy.cacheThenNetwork;
    defaultTtl = const Duration(minutes: 30);
    defaultAutoRefreshInterval = null; // disabled by default
    defaultShowLogs = kDebugMode;

    maxRetries = 2; // null means no retry
    retryDelay = const Duration(seconds: 1);
    rateLimitPerSecond = 5; // null disables rate limiting
  }
}
```

Override any of these per call by passing the corresponding parameter to `onRequest<T>()`.

---

### FAQ

- **Does this force any HTTP client?** No. Pass any async function to `request`.
- **Is the cache only strings?** Any JSON‑encodable value is supported; non‑encodable values are stored via `toString()`.
- **How do I clear cache?** Use `CustomCacheManager.deleteCache(key)` or `deleteAll()` (access it via `sl<CustomCacheManager>()`).
- **Streams?** `onRequest` is callback‑based (fire‑and‑forget). Use `cacheThenNetwork` and auto‑refresh for stream‑like behavior.

---

### License

This project is licensed under the terms of the MIT license. See `LICENSE` for details.
