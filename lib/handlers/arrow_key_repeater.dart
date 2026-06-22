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

    _timer = Timer(_initialDelay, () {
      if (!_running) return;
      _timer = null;

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