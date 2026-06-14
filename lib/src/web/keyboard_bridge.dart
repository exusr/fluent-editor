import 'keyboard_bridge_stub.dart'
    if (dart.library.html) 'keyboard_bridge_web.dart';

/// Mobile keyboard bridge for Flutter Web.
/// 
/// On mobile web, Flutter's custom RenderObject canvas doesn't trigger the browser's
/// virtual keyboard. This bridge injects a hidden native <textarea> into the DOM and
/// manages its focus to show/hide the keyboard, then forwards input events to the editor.
class MobileKeyboardBridge {
  MobileKeyboardBridge._internal();

  static final MobileKeyboardBridge instance = MobileKeyboardBridge._internal();

  final MobileKeyboardBridgeImpl _impl = MobileKeyboardBridgeImpl.instance;

  /// Initialize the hidden textarea element.
  /// This should be called once when the app starts.
  void initialize() {
    _impl.initialize();
  }

  /// Show the virtual keyboard by focusing the hidden textarea.
  /// Must be called synchronously within a user gesture handler on iOS.
  void showKeyboard() {
    _impl.showKeyboard();
  }

  /// Hide the virtual keyboard by blurring the hidden textarea.
  void hideKeyboard() {
    _impl.hideKeyboard();
  }

  /// Clean up resources when the bridge is no longer needed.
  void dispose() {
    _impl.dispose();
  }
}
