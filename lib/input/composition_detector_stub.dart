// Stub for non-web platforms. Composition detection is only needed on web
// where InputEvent.isComposing is unreliable (iOS Safari WebKit bug).
class CompositionDetector {
  CompositionDetector._internal();

  static bool isComposing = false;

  static void initialize() {}

  static void dispose() {}
}
