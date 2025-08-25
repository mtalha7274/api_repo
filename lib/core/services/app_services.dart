import 'package:shared_preferences/shared_preferences.dart';

import '../../data/managers/custom_cache_manager.dart';
import '../../data/managers/local_storage_manager.dart';
import '../../data/managers/shared_preference_manager.dart';

class AppServices {
  AppServices._internal();
  static final AppServices instance = AppServices._internal();

  SharedPreferences? _sharedPreferences;
  LocalStorageManager? _localStorageManager;
  CustomCacheManager? _customCacheManager;
  Future<void>? _initializing;

  bool get isInitialized =>
      _sharedPreferences != null &&
      _localStorageManager != null &&
      _customCacheManager != null;

  Future<void> _initialize() async {
    if (isInitialized) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }
    _initializing = () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _sharedPreferences = prefs;
      _localStorageManager = SharedPreferenceManager(prefs);
      _customCacheManager = CustomCacheManager(_localStorageManager!);
    }();
    try {
      await _initializing;
    } finally {
      _initializing = null;
    }
  }

  Future<SharedPreferences> get sharedPreferences async {
    if (!isInitialized) await _initialize();
    return _sharedPreferences!;
  }

  Future<LocalStorageManager> get localStorageManager async {
    if (!isInitialized) await _initialize();
    return _localStorageManager!;
  }

  Future<CustomCacheManager> get cacheManager async {
    if (!isInitialized) await _initialize();
    return _customCacheManager!;
  }
}
