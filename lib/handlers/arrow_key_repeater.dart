// arrow_key_repeater.dart
//
// WORKAROUND for a Linux desktop (GTK embedder) issue where, during native
// keyboard autorepeat, KeyRepeatEvent is delivered correctly and the
// underlying document/cursor state updates on every repeat (confirmed via
// logging), but the visual repaint of the selection highlight does not
// occur until the key is released. Neither markNeedsPaint(),
// ensureVisualUpdate(), scheduleFrame(), nor scheduleWarmUpFrame() force a
// frame during this state — the compositor vsync appears to be starved by
// the synchronous autorepeat event loop.
//
// Fix: on Linux, native KeyRepeatEvent for arrow keys is ignored entirely,
// and repetition is instead driven by a Dart Timer.periodic, which runs
// outside the autorepeat event delivery and triggers normal frame
// scheduling correctly.
//
// On other platforms (macOS, Windows, Web, Android, iOS) this class is
// inert: native KeyRepeatEvent is left untouched and handled as before.
//
// Remove this workaround if/when the upstream Flutter/Linux embedder issue
// is fixed.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

typedef ArrowKeyHandler = void Function(KeyEvent event);

class ArrowKeyRepeater {
  ArrowKeyRepeater(this._onRepeat);

  final ArrowKeyHandler _onRepeat;

  static final bool _active = !kIsWeb && Platform.isLinux;

  /// Whether this workaround is active on the current platform.
  /// When false, native KeyRepeatEvent should be handled normally.
  bool get isActive => _active;

  Timer? _timer;
  Ticker? _ticker;
  KeyEvent? _lastEvent;
  bool _running = false;

  static const Duration _initialDelay = Duration(milliseconds: 250);

  bool isArrowKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
  }

  /// Starts manual repetition for [event].
  /// Uses a frame-aligned ticker so repetition never exceeds the display
  /// refresh rate and cannot starve the compositor thread.
  void start(KeyEvent event, {bool fast = false}) {
    if (!_active) return;
    stop();
    _lastEvent = event;
    _running = true;

    // Initial delay (same as native key repeat).
    _timer = Timer(_initialDelay, () {
      if (!_running) return;
      _timer = null;

      // Drive repeats with a Ticker that fires once per frame.
      // This guarantees the event rate never exceeds what Flutter can
      // actually render, preventing the 66 Hz timer from flooding the
      // main thread with work faster than it can be painted.
      _ticker = Ticker((_) {
        if (!_running) return;
        final last = _lastEvent;
        if (last != null) _onRepeat(last);
      });
      _ticker!.start();
    });
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _ticker?.dispose();
    _ticker = null;
    _lastEvent = null;
  }
}