/// Lightweight profiler for identifying hot paths in the editor.
/// All methods are no-ops in release builds; profiling is active only
/// in debug/profile mode.
library;

import 'dart:developer' as developer;

bool get _enabled {
  bool isDebug = false;
  assert(() {
    isDebug = true;
    return true;
  }());
  return isDebug;
}

/// Logs a single measurement to the Flutter DevTools timeline.
void perfLog(String name, int microseconds) {
  if (!_enabled) return;
  developer.Timeline.instantSync(name, arguments: {
    'duration_us': microseconds,
    'category': 'fluent_editor',
  });
}

/// Wraps [fn] with timing and logs the result.
T perfMeasure<T>(String name, T Function() fn) {
  if (!_enabled) return fn();
  final stopwatch = Stopwatch()..start();
  try {
    return fn();
  } finally {
    stopwatch.stop();
    perfLog(name, stopwatch.elapsedMicroseconds);
  }
}

/// Async variant of [perfMeasure].
Future<T> perfMeasureAsync<T>(String name, Future<T> Function() fn) async {
  if (!_enabled) return fn();
  final stopwatch = Stopwatch()..start();
  try {
    return await fn();
  } finally {
    stopwatch.stop();
    perfLog(name, stopwatch.elapsedMicroseconds);
  }
}
