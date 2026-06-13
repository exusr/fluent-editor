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
  KeyEvent? _lastEvent;

  static const Duration _initialDelay = Duration(milliseconds: 250);
  static const Duration _interval = Duration(milliseconds: 30);
  static const Duration _intervalFast = Duration(milliseconds: 15);

  bool isArrowKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown;
  }

  /// Starts manual repetition for [event]. [fast] selects a shorter
  /// interval (e.g. for selection extension with shift held).
  void start(KeyEvent event, {bool fast = false}) {
    if (!_active) return;
    stop();
    _lastEvent = event;
    final interval = fast ? _intervalFast : _interval;
    _timer = Timer(_initialDelay, () {
      _timer = Timer.periodic(interval, (_) {
        final last = _lastEvent;
        if (last != null) {
          _onRepeat(last);
        }
      });
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _lastEvent = null;
  }
}