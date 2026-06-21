# Integration Tests

## Running tests

**Note:** On Linux, run each file separately — the Linux desktop app may fail to
restart between files when multiple test files are passed in a single command.

```bash
# Desktop tests on Linux (run each file separately)
flutter test integration_test/ime_integration_test.dart -d linux
flutter test integration_test/keyboard_integration_test.dart -d linux

# Desktop-only tests (Ctrl shortcuts, key repeat)
flutter test integration_test/keyboard_integration_test.dart --tags desktop -d linux

# Mobile tests on Android emulator/device
flutter test integration_test/touch_integration_test.dart -d <device>

# All tests except mobile (on desktop)
flutter test integration_test/ --exclude-tags mobile -d linux

# All tests except desktop (on mobile)
flutter test integration_test/ --exclude-tags desktop -d <device>
```

## Tags

| Tag | Tests | Description |
|-----|-------|-------------|
| `desktop` | Ctrl+A, Ctrl+B, Ctrl+Z, key repeat | Requires physical keyboard with Ctrl modifiers and key repeat |
| `mobile` | All touch tests | Requires touch input (tap, double tap, drag, long press) |
| _(none)_ | IME tests, arrow/home/end navigation | Works on both desktop and mobile |

## Files

- **`ime_integration_test.dart`** — Native IME: typing, enter key, backspace (uses `testTextInput.updateEditingValue`)
- **`keyboard_integration_test.dart`** — Keyboard navigation, shortcuts, key repeat
- **`touch_integration_test.dart`** — Touch gestures: tap, double tap, drag selection, scroll vs tap

## Notes

- IME tests use `tester.testTextInput.updateEditingValue` to simulate native text
  input, because `sendKeyEvent` with `character:` is intercepted by the IME handler
  on desktop (the editor delegates character input to the platform TextInput channel).
- Backspace on desktop may be handled by either the key event handler or the IME
  delta path depending on platform. Tests handle both paths.
