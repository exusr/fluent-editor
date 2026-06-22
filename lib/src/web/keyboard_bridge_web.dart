import 'dart:html' as html;

/// Web implementation of the mobile keyboard bridge.
/// Uses dart:html to inject a hidden textarea and manage the virtual keyboard.
class MobileKeyboardBridgeImpl {
  MobileKeyboardBridgeImpl._internal();

  static final MobileKeyboardBridgeImpl instance = MobileKeyboardBridgeImpl._internal();

  html.TextAreaElement? _hiddenInput;
  bool _isInitialized = false;
  html.EventListener? _keyDownListener;
  html.EventListener? _inputListener;

  void initialize() {
    if (_isInitialized) return;

    _hiddenInput = html.TextAreaElement();
    _hiddenInput!.style.position = 'fixed';
    _hiddenInput!.style.top = '-9999px';
    _hiddenInput!.style.left = '-9999px';
    _hiddenInput!.style.opacity = '0';
    _hiddenInput!.style.fontSize = '16px'; // Prevents iOS zoom
    _hiddenInput!.style.width = '1px';
    _hiddenInput!.style.height = '1px';
    _hiddenInput!.style.pointerEvents = 'none'; // Don't intercept pointer events
    _hiddenInput!.setAttribute('autocorrect', 'off');
    _hiddenInput!.setAttribute('autocapitalize', 'off');
    _hiddenInput!.setAttribute('spellcheck', 'false');
    _hiddenInput!.setAttribute('autocomplete', 'off');

    _inputListener = (html.Event event) {
      _handleInput(event);
    };
    _hiddenInput!.addEventListener('input', _inputListener);

    _keyDownListener = (html.Event event) {
      if (event is html.KeyboardEvent) {
        _handleKeyDown(event);
      }
    };
    _hiddenInput!.addEventListener('keydown', _keyDownListener);

    html.document.body?.append(_hiddenInput!);
    _isInitialized = true;
  }

  void showKeyboard() {
    if (_hiddenInput == null) return;
    _hiddenInput!.focus();
  }

  void hideKeyboard() {
    if (_hiddenInput == null) return;
    _hiddenInput!.blur();
  }

  void _handleInput(html.Event event) {
    if (_hiddenInput == null) return;

    final value = _hiddenInput!.value;
    if (value == null || value.isEmpty) return;

    _hiddenInput!.value = '';
  }

  void _handleKeyDown(html.KeyboardEvent event) {
  }

  void dispose() {
    if (_hiddenInput == null) return;

    if (_inputListener != null) {
      _hiddenInput!.removeEventListener('input', _inputListener);
    }
    if (_keyDownListener != null) {
      _hiddenInput!.removeEventListener('keydown', _keyDownListener);
    }
    _hiddenInput!.remove();
    _hiddenInput = null;
    _isInitialized = false;
  }
}
