import 'package:fluent_editor/fluent_document.dart';
import 'package:flutter/widgets.dart';

/// Document cursor.
///
/// DATA MODEL: the cursor directly stores `(fragmentId, localOffset)`,
/// where `fragmentId` is the id of a leaf Fragment and `localOffset` is the offset
/// within the text of that fragment.
///
/// [preferredX] replaces the old [preferredColumn] (integer index):
/// it is the x coordinate in pixels of the caret at the start of a vertical
/// sequence. It is preserved during consecutive Up/Down and reset to -1.0
/// by Left/Right and click.
class Cursor extends ChangeNotifier {
  String _anchorId = '';
  int _anchorOffset = 0;
  String _focusId = '';
  int _focusOffset = 0;

  String get anchorId => _anchorId;
  int get anchorOffset => imeComposing ? imeComposingStart : _anchorOffset;
  String get focusId => _focusId;
  int get focusOffset => imeComposing ? imeComposingStart : _focusOffset;

  /// Preferred x coordinate for vertical navigation (Up/Down).
  /// -1.0 = to recalculate (reset after Left/Right/click).
  double preferredX = -1.0;

  /// True when an IME composition is active. During composition the cursor
  /// is visually locked at [imeComposingStart] so the user sees a stable
  /// insertion point while the preedit text changes.
  bool imeComposing = false;

  /// The local offset where the active IME composition started. The cursor
  /// caret is painted at this position during composition.
  int imeComposingStart = 0;

  bool _suppressNotifications = false;

  set anchorId(String value) {
    if (_anchorId == value) return;
    _anchorId = value;
    if (!_suppressNotifications) notifyListeners();
  }

  set anchorOffset(int value) {
    if (_anchorOffset == value) return;
    _anchorOffset = value;
    if (!_suppressNotifications) notifyListeners();
  }

  set focusId(String value) {
    if (_focusId == value) return;
    _focusId = value;
    if (!_suppressNotifications) notifyListeners();
  }

  set focusOffset(int value) {
    if (_focusOffset == value) return;
    _focusOffset = value;
    if (!_suppressNotifications) notifyListeners();
  }

  /// Executes [fn] with notifications suppressed, then notifies once.
  void batchUpdate(void Function() fn) {
    _suppressNotifications = true;
    fn();
    _suppressNotifications = false;
    notifyListeners();
  }

  late FluentDocument document;

  Cursor({
    String? anchorId,
    int? anchorOffset,
    String? focusId,
    int? focusOffset,
  })  : _anchorId = anchorId ?? '',
        _anchorOffset = anchorOffset ?? 0,
        _focusId = focusId ?? '',
        _focusOffset = focusOffset ?? 0;

  bool get isCollapsed =>
      anchorId == focusId && anchorOffset == focusOffset;

  void forward() {
    focusOffset++;
    anchorOffset++;
  }

  /// Moves the cursor (collapsed) to (fragmentId, localOffset).
  /// Resets preferredX: a click or horizontal movement cancels the column.
  void moveTo(String fragmentId, int localOffset, {bool forward = true}) {
    preferredX = -1.0; // ← explicit reset
    anchorId = fragmentId;
    anchorOffset = localOffset;
    focusId = fragmentId;
    focusOffset = localOffset;
  }

  /// Updates only the focus (to extend selection, e.g.: shift+arrow, drag).
  void focusTo(String fragmentId, int localOffset, {bool forward = true}) {
    focusId = fragmentId;
    focusOffset = localOffset;
  }

  @override
  String toString() {
    return 'Cursor(anchorId: $anchorId, anchorOffset: $anchorOffset, '
        'focusId: $focusId, focusOffset: $focusOffset)';
  }

}