// arrow_key_repeater.dart
//
// WORKAROUND for platforms where native KeyRepeatEvent is not delivered
// reliably (Linux GTK embedder missing repaint, iOS/macOS physical
// keyboard not generating repeat events).
//
// On Linux: during native autorepeat, KeyRepeatEvent is delivered but the
// visual repaint of the selection highlight does not occur until the key is
// released. The compositor vsync appears to be starved by the synchronous
// autorepeat event loop.
//
// On iOS/macOS with physical keyboard: KeyRepeatEvent is not generated at
// all by the embedder, so holding a key only fires once.
//
// Fix: on Linux, iOS and macOS, native KeyRepeatEvent is ignored entirely
// for supported keys, and repetition is instead driven by a Dart Timer +
// Ticker, which runs outside the autorepeat event delivery and triggers
// normal frame scheduling correctly.
//
// On other platforms (Windows, Web, Android) this class is inert: native
// KeyRepeatEvent is left untouched and handled as before.
//
// Remove this workaround if/when the upstream Flutter embedder issues are
// fixed.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

typedef ArrowKeyHandler = void Function(KeyEvent event);

class ArrowKeyRepeater {
  ArrowKeyRepeater(this._onRepeat);

  final ArrowKeyHandler _onRepeat;

  static final bool _active = !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isIOS);

  /// Whether this workaround is active on the current platform.
  /// When false, native KeyRepeatEvent should be handled normally.
  bool get isActive => _active;

  Timer? _timer;
  Ticker? _ticker;
  KeyEvent? _lastEvent;
  bool _running = false;

  static const Duration _initialDelay = Duration(milliseconds: 250);

  bool supportsRepeat(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.keyZ;
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