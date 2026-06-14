/// Stub implementation for native platforms.
/// On native platforms, the keyboard bridge is a no-op since
/// the native keyboard works automatically.
class MobileKeyboardBridgeImpl {
  MobileKeyboardBridgeImpl._internal();

  static final MobileKeyboardBridgeImpl instance = MobileKeyboardBridgeImpl._internal();

  void initialize() {
    // No-op on native platforms
  }

  void showKeyboard() {
    // No-op on native platforms
  }

  void hideKeyboard() {
    // No-op on native platforms
  }

  void dispose() {
    // No-op on native platforms
  }
}
