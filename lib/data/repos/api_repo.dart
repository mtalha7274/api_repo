import 'dart:async';

import '../../core/utils/helpers.dart';
import '../../core/services/app_services.dart';
import '../managers/cache_policy.dart';
import '../managers/custom_cache_manager.dart';
import '../managers/local_storage_manager.dart';

/// Source of the data delivered to onData callback
/// - cache: came from local cache
/// - network: result of network fetch
enum ResponseOrigin { cache, network }

/// [ApiRepo] Mixin
///
/// Provides unified handling of:
/// - Local storage cache (TTL-aware)
/// - Retry + Rate limiting
/// - Auto-refreshing API requests
/// - Execution time logging
///
mixin ApiRepo {
  /// Local storage manager
  LocalStorageManager? defaultStorageManager;

  /// Auto refresh controllers
  final Map<String, Timer> _autoRefreshTimers = {};

  /// How many times to retry API call. `null` means no retry by default.
  int? maxRetries;

  /// Delay between retries
  Duration retryDelay = const Duration(seconds: 1);

  /// API calls per second allowed
  int? rateLimitPerSecond;

  /// Last API call timestamps (for rate-limiting)
  final Map<String, DateTime> _lastCallTimes = {};

  /// Default auto refresh interval when not provided per-call. `null` disables auto-refresh.
  Duration? defaultAutoRefreshInterval;

  /// Default TTL for cache entries when not provided per-call. `null` means no auto-expiration.
  Duration? defaultTtl;

  /// Default cache policy when not provided per-call.
  CachePolicy defaultCachePolicy = CachePolicy.cacheThenNetwork;

  /// Default logging flag when not provided per-call.
  bool defaultShowLogs = false;

  /// Makes a unified request that handles caching, optional serialization, timing, optional
  /// auto-refreshing, rate-limiting and graceful retry logic.
  ///
  /// Returns a [Future<T?>] containing the first result (from cache or network depending on
  /// the [cachePolicy]). Users who only need a one-time result can simply `await` this method.
  /// Users who want continuous updates (e.g. with auto-refresh) should provide [onData].
  ///
  /// [onData] is optional. When provided, it is called for every data delivery (cache hit,
  /// network response, auto-refresh tick). When omitted, data is still returned via the Future.
  ///
  /// [onError] is optional. When provided, it is called with the error and its [StackTrace]
  /// whenever a failure occurs (network, cache, auto-refresh, etc.).
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
  }) {
    final callerFunctionName = _getCallerFunctionName();
    key = key ?? callerFunctionName;

    final bool effectiveShowLogs = showLogs ?? defaultShowLogs;
    final Duration? effectiveAutoRefreshInterval =
        autoRefreshInterval ?? defaultAutoRefreshInterval;
    final Duration? effectiveTtl = ttl ?? defaultTtl;
    final CachePolicy effectiveCachePolicy = cachePolicy ?? defaultCachePolicy;
    final LocalStorageManager? effectiveStorageManager =
        storageManager ?? defaultStorageManager;

    if (effectiveShowLogs) {
      printLog('🔑 key: $key, caller: $callerFunctionName');
    }

    return _request<T>(
      key,
      autoRefreshInterval: effectiveAutoRefreshInterval,
      request: request,
      onData: onData,
      onError: onError,
      ttl: effectiveTtl,
      maxRetriesOverride: maxRetries,
      retryDelayOverride: retryDelay,
      rateLimitPerSecondOverride: rateLimitPerSecond,
      cachePolicy: effectiveCachePolicy,
      showLogs: effectiveShowLogs,
      storageManagerOverride: effectiveStorageManager,
    );
  }

  Future<T?> _request<T>(
    String key, {
    required FutureOr<T> Function() request,
    void Function(T data, ResponseOrigin origin)? onData,
    void Function(Object error, StackTrace stackTrace)? onError,
    Duration? autoRefreshInterval,
    Duration? ttl,
    int? maxRetriesOverride,
    Duration? retryDelayOverride,
    int? rateLimitPerSecondOverride,
    CachePolicy cachePolicy = CachePolicy.cacheThenNetwork,
    bool showLogs = false,
    LocalStorageManager? storageManagerOverride,
  }) async {
    final CustomCacheManager cacheManager = storageManagerOverride != null
        ? CustomCacheManager(storageManagerOverride)
        : await AppServices.instance.cacheManager;

    T? result;

    void deliver(T data, ResponseOrigin origin) {
      result ??= data;
      onData?.call(data, origin);
    }

    FutureOr<T?> readCache({bool allowExpired = false}) async {
      final sw = Stopwatch()..start();
      final dynamic cachedRaw = await cacheManager.getCache(
        key: key,
        allowExpired: allowExpired,
      );
      sw.stop();
      if (showLogs) {
        printLog(
          '🗄️  Cache read (${allowExpired ? 'allowExpired' : 'fresh'}) in ${sw.elapsedMs()}',
        );
      }
      if (cachedRaw == null) return null;
      try {
        final T value = cachedRaw as T;
        return value;
      } catch (e) {
        if (showLogs) printLog('⚠️  Cache deserialize failed: $e');
        return null;
      }
    }

    Future<T?> fetchNetwork() async {
      final int? rate = rateLimitPerSecondOverride ?? rateLimitPerSecond;
      if (rate.isEnabled) {
        final minIntervalMs = (1000 / rate!).floor();
        final last = _lastCallTimes[key];
        if (last != null) {
          final elapsed = DateTime.now().difference(last).inMilliseconds;
          final waitMs = minIntervalMs - elapsed;
          if (waitMs > 0) {
            if (showLogs) printLog('⏳ Rate limit: waiting ${waitMs}ms');
            await Future.delayed(waitMs.ms);
          }
        }
        _lastCallTimes[key] = DateTime.now();
      }

      final int? effectiveMaxRetries = maxRetriesOverride ?? maxRetries;
      if (effectiveMaxRetries != null && effectiveMaxRetries < 0) {
        throw ArgumentError(
          'maxRetries cannot be negative. Received: $effectiveMaxRetries',
        );
      }
      final int retries = (effectiveMaxRetries ?? 0).clamp(0, 10);
      final Duration baseDelay = retryDelayOverride ?? retryDelay;

      int attempt = 0;
      while (true) {
        final sw = Stopwatch()..start();
        try {
          final T raw = await request();
          sw.stop();
          if (showLogs) printLog('🌐 Network in ${sw.elapsedMs()}');
          unawaited(cacheManager.setCache(key: key, value: raw, ttl: ttl));
          return raw;
        } catch (e) {
          sw.stop();
          if (attempt >= retries) {
            if (showLogs) {
              printLog('❌ Network failed after ${attempt + 1} attempt(s): $e');
            }
            rethrow;
          }
          attempt += 1;
          final Duration nextDelay = Duration(
            milliseconds: baseDelay.inMilliseconds * attempt,
          );
          if (showLogs) {
            printLog('🔁 Retry #$attempt in ${nextDelay.inMilliseconds}ms');
          }
          await Future.delayed(nextDelay);
        }
      }
    }

    try {
      if (showLogs) printLog('📦 Policy: ${cachePolicy.name}');

      switch (cachePolicy) {
        case CachePolicy.cacheOnly:
          final T? cached = await readCache(allowExpired: false);
          if (cached != null) deliver(cached, ResponseOrigin.cache);
          break;

        case CachePolicy.networkOnly:
          final T value = (await fetchNetwork()) as T;
          deliver(value, ResponseOrigin.network);
          break;

        case CachePolicy.cacheFirst:
          final T? cached = await readCache(allowExpired: false);
          if (cached != null) {
            deliver(cached, ResponseOrigin.cache);
          } else {
            final T value = (await fetchNetwork()) as T;
            deliver(value, ResponseOrigin.network);
          }
          break;

        case CachePolicy.networkFirst:
          try {
            final T value = (await fetchNetwork()) as T;
            deliver(value, ResponseOrigin.network);
          } catch (e, st) {
            onError?.call(e, st);
            final T? cached = await readCache(allowExpired: true);
            if (cached != null) deliver(cached, ResponseOrigin.cache);
          }
          break;

        case CachePolicy.cacheThenNetwork:
          final T? cached = await readCache(allowExpired: false);
          if (cached != null) {
            deliver(cached, ResponseOrigin.cache);
            unawaited(
              Future<void>(() async {
                try {
                  final T? value = await fetchNetwork();
                  if (value != null) deliver(value, ResponseOrigin.network);
                } catch (e, st) {
                  if (showLogs) printLog('⚠️  Network update failed: $e');
                  onError?.call(e, st);
                }
              }),
            );
          } else {
            final T value = (await fetchNetwork()) as T;
            deliver(value, ResponseOrigin.network);
          }
          break;
      }

      if (autoRefreshInterval.isEnabled) {
        _autoRefreshTimers[key]?.cancel();
        _autoRefreshTimers[key] = Timer.periodic(autoRefreshInterval!, (
          _,
        ) async {
          if (showLogs) printLog('🔄 Auto-refresh tick for $key');
          try {
            final T? value = await fetchNetwork();
            if (value != null) deliver(value, ResponseOrigin.network);
          } catch (e, st) {
            if (showLogs) printLog('⚠️  Auto-refresh failed: $e');
            onError?.call(e, st);
          }
        });
      }
    } catch (e, st) {
      if (showLogs) printLog('⚠️  Request error: $e');
      onError?.call(e, st);
    }

    return result;
  }

  String _getCallerFunctionName() {
    final traceLines = StackTrace.current.toString().split('\n');
    final callerLine = traceLines.length > 2 ? traceLines[2] : '';
    final match = RegExp(r'#\d+\s+([^\s]+)').firstMatch(callerLine);
    return match?.group(1) ?? 'unknown_function';
  }
}

// Memory cache removed; using disk cache only via CustomCacheManager.

void unawaited(Future<void> future) {}

extension _NumExt on num {
  Duration get ms => Duration(milliseconds: toInt());
}

extension _StopwatchLog on Stopwatch {
  String elapsedMs() => '${elapsedMilliseconds}ms';
}

extension _NullableDuration on Duration? {
  bool get isEnabled => this != null;
}

extension _NullableInt on int? {
  bool get isEnabled => this != null && this! > 0;
}

extension _CachePolicyName on CachePolicy {
  String get name => toString().split('.').last;
}
