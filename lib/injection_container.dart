import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/managers/custom_cache_manager.dart';
import 'data/managers/local_store_manager.dart';
import 'data/repos/api_repo.dart';

final sl = GetIt.instance;

Future<void> initializeDependencies() async {
  // Initialize
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(sharedPreferences);

  // Managers
  sl.registerSingleton<LocalStorageManager>(
    SharedPreferenceManager(sl<SharedPreferences>()),
  );
  sl.registerSingleton<CustomCacheManager>(
    CustomCacheManager(sl<LocalStorageManager>()),
  );
}
