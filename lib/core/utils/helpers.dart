import 'package:flutter/foundation.dart';

import '../../config/config.dart';

void printLog(Object? message, {String prefix = Config.logPrefix}) {
  debugPrint('$prefix ${message ?? ''}');
}
