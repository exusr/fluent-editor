/// Stub implementation for native platforms.
/// On native platforms, the keyboard bridge is a no-op since
/// the native keyboard works automatically.
class MobileKeyboardBridgeImpl {
  MobileKeyboardBridgeImpl._internal();

  static final MobileKeyboardBridgeImpl instance = MobileKeyboardBridgeImpl._internal();

  void initialize() {
  }

  void showKeyboard() {
  }

  void hideKeyboard() {
  }

  void dispose() {
  }
}
