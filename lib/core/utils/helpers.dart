void printLog(Object? message, {String prefix = Config.logPrefix}) {
  debugPrint('$prefix ${message ?? ''}');
}
