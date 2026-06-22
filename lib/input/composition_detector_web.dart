import 'dart:html' as html;

class CompositionDetector {
  CompositionDetector._internal();

  static bool isComposing = false;
  static bool _initialized = false;
  static html.EventListener? _startListener;
  static html.EventListener? _endListener;

  static void initialize() {
    if (_initialized) return;
    _startListener = (html.Event event) {
      isComposing = true;
    };
    _endListener = (html.Event event) {
      isComposing = false;
    };
    html.document.addEventListener('compositionstart', _startListener);
    html.document.addEventListener('compositionend', _endListener);
    _initialized = true;
  }

  static void dispose() {
    if (!_initialized) return;
    if (_startListener != null) {
      html.document.removeEventListener('compositionstart', _startListener);
    }
    if (_endListener != null) {
      html.document.removeEventListener('compositionend', _endListener);
    }
    _startListener = null;
    _endListener = null;
    _initialized = false;
    isComposing = false;
  }
}
