import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart' show Fragment;
import 'package:fluent_editor/handlers/handle_insert_character.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/handlers/handle_enter.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';

/// Singleton IME handler that implements [TextInputClient] for Flutter's
/// system text input channel. Preedit text is kept isolated from the document
/// model and only committed when the composition genuinely ends.
class FluentTextInputHandler with DeltaTextInputClient {
  static final FluentTextInputHandler _instance = FluentTextInputHandler._internal();
  factory FluentTextInputHandler() => _instance;
  FluentTextInputHandler._internal();

  TextInputConnection? _connection;
  FluentDocument? _document;

  /// Platforms where the native text input system expects the IME buffer to
  /// stay synchronised with the document text (iOS virtual keyboard, macOS
  /// NSTextInputContext, and Windows). When active the buffer mirrors the current fragment
  /// text so autocorrect, predictive text and CJK composition work correctly.
  bool get _shouldSyncBuffer =>
      kIsWeb || (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS ||
                  defaultTargetPlatform == TargetPlatform.windows);

  /// True on iOS specifically. Used to scope the empty-fragment placeholder
  /// (see [_emptyFragmentPlaceholder]) and other iOS-only quirks, since
  /// macOS handles Backspace via the hardware KeyEvent path and Windows has
  /// not exhibited the empty-buffer symptom.
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Public accessor so the editor shell knows whether backspace is handled
  /// via deltas (buffer-sync) rather than raw KeyEvent.
  bool get shouldUseBufferSync => _shouldSyncBuffer;

  /// Current preedit text displayed to the user but not yet committed.
  String _preeditText = '';
  String get preeditText => _preeditText;

  /// Offset in the document (fragment id + local offset) where preedit starts.
  String _preeditFragmentId = '';
  int _preeditLocalOffset = 0;
  String _preeditContainerId = '';

  /// Caret position WITHIN the preedit/marked text (0.._preeditText.length).
  /// Used to position the IME candidate window so it follows the caret as the
  /// user types or navigates inside the composition.
  int _preeditCaretOffset = 0;

  /// Whether a composition is currently active.
  bool _isComposing = false;
  bool get isComposing => _isComposing;

  /// Fragment id where the active preedit starts.
  String get preeditFragmentId => _preeditFragmentId;

  /// Local offset where the active preedit starts.
  int get preeditLocalOffset => _preeditLocalOffset;

  /// The range within the preedit that is being composed.
  TextRange _composingRange = TextRange.empty;
  TextRange get composingRange => _composingRange;

  /// True while we are pushing a value to the platform ourselves (e.g. after
  /// a commit, to reset the IME's internal buffer) so that the resulting
  /// platform echo is not misinterpreted as new user input.
  bool _updatingSelf = false;

  /// True when we just handled an enter via delta, so performAction(newline)
  /// can be safely ignored to avoid double-splitting the paragraph.
  bool _justHandledEnter = false;

  /// On Android (_shouldSyncBuffer == false) we keep the IME buffer alive
  /// while the user types in the same fragment so suggestions/autocorrect
  /// have the correct context. We only reset the buffer when the cursor
  /// moves to a different fragment.
  String _lastSyncedFragmentId = '';

  /// Tracks the last text sent to the platform via setEditingState. On web,
  /// if the new text is shorter, we must first clear the browser's composing
  /// range with the old text before setting the new text, otherwise the
  /// browser reports a stale composing range that exceeds the new text
  /// length, triggering an assertion in TextEditingDelta.fromJSON.
  String _lastSyncedText = '';

  /// Tracks the previous selection state so syncImeBufferToFragment can
  /// detect when a selection change requires resetting the platform IME's
  /// autocorrect/predictive text context (iOS).
  String _prevSelectionKey = '';

  /// Whether the platform TextInput connection is currently open.
  bool get isConnectionActive => _connection != null && _connection!.attached;

  /// Last known caret rect (Flutter view logical coordinates).
  Rect? _lastCaretRect;

  /// Last known Flutter view height in logical pixels.
  double? _lastViewHeight;

  /// Retry mechanism for Windows "view ID is null" timing issue.
  Timer? _connectionRetryTimer;
  int _connectionRetryCount = 0;
  static const int _maxConnectionRetries = 5;
  static const List<Duration> _windowsRetryDelays = [
    Duration(milliseconds: 50),
    Duration(milliseconds: 100),
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];

  /// True after a structural document change (e.g. paragraph split via
  /// Enter) so that platform echoes still referring to the old buffer
  /// are ignored for a short grace period.
  bool _structuralChangeInProgress = false;
  Timer? _structuralChangeTimer;
  static const Duration _structuralChangeGracePeriod =
      Duration(milliseconds: 300);

  /// Call this whenever the Flutter view height is known (e.g. in
  /// _updateImeCaretRect). Stores the height and re-sends the transform
  /// so the macOS plugin can map caret rect → screen rect correctly.
  ///
  /// The macOS FlutterTextInputPlugin applies _editableTransform to the
  /// caret rect before calling [fromView convertRect:toView:nil]. Without
  /// a Y-flip the plugin treats Flutter's top-left Y as Cocoa's bottom-left Y,
  /// Stores the Flutter view height and sends an explicit identity
  /// transform to reset any previously-set (potentially corrupted)
  /// _editableTransform in the macOS plugin.
  void setViewHeight(double viewHeight) {
    _lastViewHeight = viewHeight;
    if (_connection == null || !_connection!.attached) return;
    // On web, setEditableSizeAndTransform is handled by _updateWebImePosition()
    // which sends the real render box transform. Don't override it with a dummy.
    if (kIsWeb) return;
    _connection!.setEditableSizeAndTransform(
      const Size(9999, 9999),
      Matrix4.identity(),
    );
  }

  /// On web, Flutter's engine ignores [setCaretRect]/[setComposingRect] (they
  /// are no-ops). Instead, the browser positions IME popups based on the hidden
  /// <textarea>'s size, transform, and font style.
  ///
  /// The textarea contains only the current fragment's text (synced via
  /// [syncImeBufferToFragment]). The browser's internal caret is at
  /// `cursor_offset * char_width` from the textarea's left edge. To make this
  /// coincide with Flutter's real caret, the textarea must be positioned at the
  /// fragment's start within the paragraph (which accounts for previous
  /// fragments' widths and paragraph alignment offset).
  void _updateWebImePosition() {
    if (_connection == null || !_connection!.attached) return;
    if (_document == null) return;
    final doc = _document!;

    final fragId = doc.cursor.focusId.isNotEmpty
        ? doc.cursor.focusId
        : doc.cursor.anchorId;
    if (fragId.isEmpty) return;

    final containerId = doc.findLogicalContainerId(fragId);
    if (containerId == null) return;

    final render = doc.paragraphRegistry.renderFor(containerId);
    if (render == null || !render.attached || !render.hasSize) return;

    // Resolve font metrics from the current fragment.
    String fontFamily = 'DejaVu Sans';
    double fontSize = 14.0;
    FontWeight fontWeight = FontWeight.normal;
    final fragNode = doc.nodeById(fragId);
    if (fragNode is Fragment) {
      fontFamily = fragNode.fontFamily;
      fontSize = fragNode.fontSize;
      fontWeight = fragNode.isBold ? FontWeight.bold : FontWeight.normal;
    }

    // Get the screen rect of the caret at the fragment's start (offset 0).
    // This tells us where the fragment begins within the paragraph, accounting
    // for previous fragments' widths and paragraph alignment offset.
    final fragmentStartRect = render.getCaretScreenRect(fragId, 0);

    final Matrix4 transform;
    if (fragmentStartRect != null) {
      // Compute the fragment's local offset within the render box.
      final renderBoxOrigin = render.localToGlobal(Offset.zero);
      final fragOffsetX = fragmentStartRect.left - renderBoxOrigin.dx;
      final fragOffsetY = fragmentStartRect.top - renderBoxOrigin.dy;
      // Compose: render box transform × translation to fragment start.
      // This positions the textarea at the fragment's origin so the browser's
      // internal caret (at cursor_offset within the textarea) aligns with
      // Flutter's real caret.
      transform = render.getTransformTo(null)
          .multiplied(Matrix4.translationValues(fragOffsetX, fragOffsetY, 0));
    } else {
      // Fallback: use the render box transform directly.
      transform = render.getTransformTo(null);
    }

    _connection!.setEditableSizeAndTransform(
      render.size,
      transform,
    );

    // Use the fragment's font with a browser-safe fallback so the textarea's
    // character widths match Flutter's, keeping the internal caret aligned at
    // any cursor offset.
    final browserFontFamily = _webFontFallback(fontFamily);
    _connection!.setStyle(
      fontFamily: browserFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      textDirection: TextDirection.ltr,
      // Left-align within the textarea: positioning is already handled by the
      // transform above. Center/right alignment would shift the text within
      // the textarea and misalign the internal caret.
      textAlign: TextAlign.left,
    );
  }

  /// Returns a browser-safe CSS font-family string for [fontFamily].
  ///
  /// Fonts declared in pubspec.yaml's `fonts:` section are loaded as web
  /// fonts and available to the browser's hidden <textarea>. Fonts bundled
  /// only as assets (e.g. "DejaVu Sans") are NOT available, so the browser
  /// would fall back to its default font with different metrics, causing
  /// the textarea's internal caret to be offset from Flutter's real caret.
  ///
  /// For asset-only fonts we substitute a similar generic family that the
  /// browser can render. For web-font families we pass the name through
  /// with a generic fallback appended.
  String _webFontFallback(String fontFamily) {
    // Fonts declared in pubspec.yaml's fonts: section — available as web
    // fonts to the browser. Append a generic fallback just in case.
    const webFontFamilies = {
      'Crimson Text', 'Fira Sans', 'Inter', 'Lato', 'Libre Baskerville',
      'Literata', 'Lora', 'Merriweather', 'Montserrat', 'Noto Sans',
      'Noto Serif', 'Nunito', 'Open Sans', 'Oswald', 'PT Sans',
      'Playfair Display', 'Poppins', 'Quicksand', 'Raleway', 'Roboto',
      'Roboto Slab', 'Source Sans Pro', 'Titillium Web', 'Ubuntu',
      'Work Sans',
      'DejaVu Sans', 'DejaVu Sans Mono', 'DejaVu Serif',
    };

    if (webFontFamilies.contains(fontFamily)) {
      return '$fontFamily, sans-serif';
    }

    // Asset-only fonts — not available to the browser. Map to a similar
    // generic family so the textarea's metrics are close to Flutter's.
    return switch (fontFamily) {
      _ => '$fontFamily, sans-serif',
    };
  }

  /// Updates the caret rectangle so the platform can position the IME
  /// candidate window (e.g. NSTextInputContext on macOS) near the cursor.
  /// [rect] must be in Flutter view logical pixel coordinates.
  void updateCaretRect(Rect rect) {
    _lastCaretRect = rect;
    if (_connection == null || !_connection!.attached) return;
    // On web, setCaretRect/setComposingRect are no-ops. Use the real render
    // box transform + font style to position the hidden <textarea> instead.
    if (kIsWeb) {
      _updateWebImePosition();
      return;
    }
    _connection!.setCaretRect(rect);
    _connection!.setComposingRect(rect);
  }

  /// Attaches the IME connection to the given document.
  void attachInput(FluentDocument document) {
    _document = document;
    _lastSyncedFragmentId = '';
    _lastSyncedText = '';
    _prevSelectionKey = '';
  }

  /// Detaches and closes the IME connection.
  void detachInput() {
    commitIfComposing();
    _connectionRetryTimer?.cancel();
    _connectionRetryTimer = null;
    _connectionRetryCount = 0;
    _structuralChangeTimer?.cancel();
    _structuralChangeTimer = null;
    _structuralChangeInProgress = false;
    _connection?.close();
    _connection = null;
    _document = null;
    _resetComposition();
    _lastSyncedFragmentId = '';
    _lastSyncedText = '';
    _prevSelectionKey = '';
  }

  /// Opens the keyboard (requests focus from the platform text input).
  void showKeyboard(BuildContext context) {
    // Extract viewId from the current window using the context
    final int viewId = View.of(context).viewId;

    if (_connection == null || !_connection!.attached) {
      _attachConnection(viewId: viewId);
    }
    _connection?.show();
    // On web, position the hidden <textarea> using the real render box
    // transform and font style so IME popups appear next to the cursor.
    if (kIsWeb) {
      _updateWebImePosition();
      return;
    }
    // Send transform then caret rect immediately after show() so macOS
    // has everything it needs for firstRectForCharacterRange:.
    final h = _lastViewHeight;
    if (h != null) setViewHeight(h);
    final rect = _lastCaretRect;
    if (rect != null) {
      _connection?.setCaretRect(rect);
      _connection?.setComposingRect(rect);
    }
  }

  /// Hides the keyboard.
  void hideKeyboard() {
    commitIfComposing();
    _connection?.close();
  }

  bool _attachConnection({required int viewId}) {
    if (_document == null) return false;

    try {
      _connection = TextInput.attach(
        this,
        TextInputConfiguration(
          inputType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          inputAction: TextInputAction.newline,
          // Required for updateEditingValueWithDeltas to actually be called.
          // Without this, the platform sends only full TextEditingValue
          // snapshots via updateEditingValue, which is ambiguous for
          // detecting deletions against an intentionally-empty local buffer
          // (a backspace with no composition active would be indistinguishable
          // from "no change": both report text: '').
          enableDeltaModel: true,
          viewId: viewId, // Required for multi-window desktop support
        ),
      );

      // Verify connection is actually active and exists
      if (_connection == null || !_connection!.attached) {
        return false;
      }

      // Initialise the IME with an EMPTY buffer (not whatever stale preedit
      // state we might be holding). The platform's own composition buffer is
      // always considered the source of truth for what's "in progress"; our
      // _preeditText only mirrors it for rendering purposes.
      _connection!.setEditingState(const TextEditingValue());
      _connection!.show();
      // On iOS/macOS/Windows prime the platform buffer with the current fragment text
      // so the IME has context from the very first keystroke.
      if (_shouldSyncBuffer) {
        syncImeBufferToFragment();
      }
      // Reset retry count on successful attachment
      _connectionRetryCount = 0;
      _connectionRetryTimer?.cancel();
      _connectionRetryTimer = null;
      return true;
    } on PlatformException catch (e) {
      // Windows-specific retry for "view ID is null" timing issue
      if (defaultTargetPlatform == TargetPlatform.windows &&
          e.message?.contains('view ID is null') == true &&
          _connectionRetryCount < _maxConnectionRetries) {
        final delay = _windowsRetryDelays[_connectionRetryCount.clamp(0, _windowsRetryDelays.length - 1)];
        _connectionRetryCount++;
        _connectionRetryTimer?.cancel();
        _connectionRetryTimer = Timer(delay, () {
          _connectionRetryTimer = null;
          _attachConnection(viewId: viewId); // Retry with the same viewId
        });
        return false; // Return false to indicate not ready yet, WITHOUT crashing
      }
      _connection = null; // Clean up state on total failure
      return false;
    }
  }

  // ─── TextInputClient implementation ─────────────────────────────

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    if (_isComposing) {
      // On buffer-sync platforms the IME computes deltas against the full
      // fragment text. Return the reconstructed full buffer so delta
      // application stays consistent and avoids random duplication.
      if (_shouldSyncBuffer) {
        final fragText = _getCurrentFragmentText() ?? '';
        final start = _preeditLocalOffset.clamp(0, fragText.length);
        final text = fragText.substring(0, start) + _preeditText + fragText.substring(start);
        final composingStart = start;
        final composingEnd = start + _preeditText.length;
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(
            offset: composingStart + _preeditCaretOffset.clamp(0, _preeditText.length),
          ),
          composing: TextRange(start: composingStart, end: composingEnd),
        );
      }
      return TextEditingValue(
        text: _preeditText,
        selection: TextSelection.collapsed(offset: _preeditText.length),
        composing: _composingRange,
      );
    }
    // Buffer-sync platforms (web, iOS, macOS, Windows): return the actual
    // fragment text so the IME computes deltas against the correct content.
    if (_shouldSyncBuffer) {
      final text = _getCurrentFragmentText();
      if (text != null) {
        final doc = _document!;
        final cursor = doc.cursor;
        final isSingleFragSelection =
            !cursor.isCollapsed && cursor.anchorId == cursor.focusId;
        final offset = _getCursorOffsetInFragment().clamp(0, text.length);
        if (_isIOS &&
            cursor.isCollapsed &&
            offset == 0 &&
            !text.startsWith(_emptyFragmentPlaceholder)) {
          // See _emptyFragmentPlaceholder: when the cursor sits at the very
          // start of a fragment (offset 0), UIKit's Backspace has nothing
          // before the cursor to delete and silently swallows the keystroke.
          // We prepend a single zero-width placeholder character so Backspace
          // always has something to act on. The placeholder never reaches the
          // document model — it is intercepted in updateEditingValueWithDeltas
          // and translated into a structural backspace (merge with prev node).
          return TextEditingValue(
            text: '$_emptyFragmentPlaceholder$text',
            selection: const TextSelection.collapsed(offset: 1),
            composing: TextRange.empty,
          );
        }
        if (isSingleFragSelection) {
          return TextEditingValue(
            text: text,
            selection: TextSelection(
              baseOffset: cursor.anchorOffset.clamp(0, text.length),
              extentOffset: cursor.focusOffset.clamp(0, text.length),
            ),
            composing: TextRange.empty,
          );
        }
        return TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: offset),
          composing: TextRange.empty,
        );
      }
    }
    // Other platforms keep an empty buffer (backspace handled via KeyEvent).
    return const TextEditingValue();
  }

  /// Returns true if the delta's text-modification ranges are within the
  /// bounds of the text length and do not cut through UTF-16 surrogate pairs
  /// (e.g., emoji). Malformed deltas from the platform (especially web
  /// browsers) can have ranges that exceed oldText.length, which would
  /// trigger an assertion inside `delta.apply()`. Ranges that split a
  /// surrogate pair would produce corrupted text.
  bool _isDeltaRangeValid(TextEditingDelta delta, String text) {
    final textLength = text.length;
    bool isRangeSafe(int start, int end) {
      if (start < 0 || end > textLength || start > end) return false;
      // Reject ranges that cut through a surrogate pair.
      if (start > 0 && start < textLength) {
        final prev = text.codeUnitAt(start - 1);
        final curr = text.codeUnitAt(start);
        if (prev >= 0xD800 && prev <= 0xDBFF &&
            curr >= 0xDC00 && curr <= 0xDFFF) {
          return false;
        }
      }
      if (end > 0 && end < textLength) {
        final prev = text.codeUnitAt(end - 1);
        final curr = text.codeUnitAt(end);
        if (prev >= 0xD800 && prev <= 0xDBFF &&
            curr >= 0xDC00 && curr <= 0xDFFF) {
          return false;
        }
      }
      return true;
    }

    if (delta is TextEditingDeltaDeletion) {
      return isRangeSafe(delta.deletedRange.start, delta.deletedRange.end);
    }
    if (delta is TextEditingDeltaReplacement) {
      return isRangeSafe(delta.replacedRange.start, delta.replacedRange.end);
    }
    if (delta is TextEditingDeltaInsertion) {
      final offset = delta.insertionOffset;
      if (offset < 0 || offset > textLength) return false;
      if (offset > 0 && offset < textLength) {
        final prev = text.codeUnitAt(offset - 1);
        final curr = text.codeUnitAt(offset);
        if (prev >= 0xD800 && prev <= 0xDBFF &&
            curr >= 0xDC00 && curr <= 0xDFFF) {
          return false;
        }
      }
      return true;
    }
    return true;
  }

  /// Safely applies [delta] to [value], clamping the resulting selection and
  /// composing ranges to the new text length. This replaces [delta.apply()]
  /// which can trigger an assertion failure when the replacement text is
  /// shorter than the original (e.g. autocorrect suggestion) because the
  /// delta's selection/composing offsets still reference the old (longer) text.
  TextEditingValue _safeApplyDelta(TextEditingDelta delta, TextEditingValue value) {
    final String newText;
    if (delta is TextEditingDeltaInsertion) {
      newText = value.text.replaceRange(
          delta.insertionOffset, delta.insertionOffset, delta.textInserted);
    } else if (delta is TextEditingDeltaDeletion) {
      newText = value.text.replaceRange(
          delta.deletedRange.start, delta.deletedRange.end, '');
    } else if (delta is TextEditingDeltaReplacement) {
      newText = value.text.replaceRange(
          delta.replacedRange.start, delta.replacedRange.end, delta.replacementText);
    } else {
      return TextEditingValue(
        text: delta.oldText,
        selection: delta.selection,
        composing: delta.composing,
      );
    }
    final len = newText.length;
    return TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: delta.selection.baseOffset.clamp(0, len),
        extentOffset: delta.selection.extentOffset.clamp(0, len),
      ),
      composing: delta.composing.isValid
          ? TextRange(
              start: delta.composing.start.clamp(0, len),
              end: delta.composing.end.clamp(0, len),
            )
          : TextRange.empty,
    );
  }

  /// Applies a list of [deltas] sequentially to [initialValue], syncing the
  /// value to each delta's oldText before applying to avoid TextRange
  /// assertion failures when the buffer doesn't match the platform's text.
  /// Deltas whose ranges exceed oldText.length are skipped (the value is
  /// rebuilt from the delta's own selection/composing instead).
  TextEditingValue _applyDeltasSafely(
    TextEditingValue initialValue,
    List<TextEditingDelta> deltas,
  ) {
    var value = initialValue;
    for (final delta in deltas) {
      if (value.text != delta.oldText) {
        value = TextEditingValue(
          text: delta.oldText,
          selection: delta.selection,
          composing: delta.composing,
        );
      }
      if (!_isDeltaRangeValid(delta, value.text)) {
        debugPrint('FluentTextInputHandler: skipping malformed delta '
            '(range exceeds oldText length ${value.text.length}): $delta');
        value = TextEditingValue(
          text: delta.oldText,
          selection: delta.selection,
          composing: delta.composing,
        );
        continue;
      }
      value = _safeApplyDelta(delta, value);
    }
    return value;
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (_updatingSelf) return;
    if (_structuralChangeInProgress) return;
    if (_document == null) return;
    // Check if we're handling preedit/composing data - sanitize at source
    if (deltas.any((d) => d.composing.isValid)) {
      // Apply deltas to get the final value, then sanitize it
      final value = _applyDeltasSafely(
        currentTextEditingValue ?? const TextEditingValue(),
        deltas,
      );
      final cleanText = _sanitizeUtf16(value.text);
      final cleanValue = TextEditingValue(
        text: cleanText,
        selection: value.selection,
        composing: value.composing,
      );
      updateEditingValue(cleanValue);
      return;
    }

    // Our local buffer (currentTextEditingValue) is intentionally kept
    // EMPTY whenever there is no active composition — we apply finalized
    // text directly to the document and reset the platform buffer
    // immediately after. This means a pure deletion delta (backspace with
    // no composition in progress) always computes as "delete from an empty
    // string", which produces no visible text change and was silently
    // swallowed by updateEditingValue's "new composition" branch.
    //
    // Deletion deltas must be handled explicitly here, before trying to
    // reconstruct a TextEditingValue from a buffer that doesn't represent
    // real document content.
    //
    // PLATFORM QUIRK (iOS): UIKit's text input system does not reliably
    // emit TextEditingDeltaDeletion for a plain Backspace the way Android's
    // IME does. A single backspace on iOS very often arrives as a
    // TextEditingDeltaReplacement with an empty replacementText covering
    // the range to remove (effectively "replace these N characters with
    // nothing"), sometimes even when there is no real "replacement"
    // happening from the user's perspective. If we only special-case
    // TextEditingDeltaDeletion, backspace silently does nothing on iOS once
    // text has been committed, while insertion (which always arrives as a
    // proper TextEditingDeltaInsertion) keeps working — exactly the
    // reported symptom. We treat any TextEditingDeltaReplacement whose
    // replacementText is empty as a deletion too.
    if (!_isComposing) {
      // iOS/macOS/Windows: buffer is synced with fragment text, apply deltas to document.
      if (_shouldSyncBuffer) {
        final _isMacOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

        // PLATFORM QUIRK (iOS, empty paragraph): UIKit treats a completely
        // empty text buffer as having nothing for Backspace to act on —
        // pressing Backspace with text: '' produces NO callback at all (no
        // delta, no KeyEvent); UIKit swallows the keystroke before it ever
        // reaches Flutter. Since the current fragment's real text is ''
        // whenever the paragraph is empty, we mirror a single zero-width
        // placeholder character to UIKit instead (see
        // _emptyFragmentPlaceholder / syncImeBufferToFragment /
        // currentTextEditingValue) so Backspace has something real to
        // delete. When the user backspaces it, UIKit now sends a normal
        // deletion/replacement delta shrinking the placeholder buffer from
        // length 1 to 0. We intercept that exact signature here and treat
        // it as a structural backspace (merge with the previous node)
        // instead of letting it fall through and try to write the
        // placeholder into the document.
        if (_isIOS && cursorIsAtFragmentStart) {
          // On iOS we prepend a zero-width placeholder (\u200B) to the IME
          // buffer whenever the cursor is at offset 0 — whether the fragment
          // is empty or not — so Backspace always has something to delete.
          // Detect that placeholder deletion here and treat it as a
          // structural backspace (merge with the previous node).
          final deletedPlaceholder = deltas.any((d) {
            if (d is TextEditingDeltaDeletion) {
              return d.oldText.startsWith(_emptyFragmentPlaceholder) &&
                  d.deletedRange.start == 0 &&
                  d.deletedRange.end == _emptyFragmentPlaceholder.length;
            }
            if (d is TextEditingDeltaReplacement) {
              return d.oldText.startsWith(_emptyFragmentPlaceholder) &&
                  d.replacementText.isEmpty &&
                  d.replacedRange.start == 0 &&
                  d.replacedRange.end == _emptyFragmentPlaceholder.length;
            }
            return false;
          });
          if (deletedPlaceholder) {
            _document!.saveState(description: 'Backspace', forceNewAction: false);
            executeHandleBackspace(_document!);
            syncImeBufferToFragment();
            return;
          }
        }

        // PLATFORM QUIRK (iOS, non-empty fragment at offset 0): as a
        // residual safety net, also catch the case where the fragment text
        // is NOT empty (so the placeholder above does not apply) but UIKit
        // still reports a zero-content delete attempt — e.g. a batch of
        // only TextEditingDeltaNonTextUpdate entries, or a
        // Deletion/Replacement whose range is already collapsed
        // (start == end). The normal length-diff detection further below
        // only fires on an actual 1/2 character shrink, so this signature
        // would otherwise fall through to updateEditingValue() and be
        // swallowed by the "skip our own echo" guard.
        if (_isIOS && cursorIsAtFragmentStart && deltas.isNotEmpty) {
          final isZeroContentDeleteAttempt = deltas.every((d) {
            if (d is TextEditingDeltaNonTextUpdate) return true;
            if (d is TextEditingDeltaDeletion) {
              return d.deletedRange.start == d.deletedRange.end;
            }
            if (d is TextEditingDeltaReplacement) {
              return d.replacementText.isEmpty &&
                  d.replacedRange.start == d.replacedRange.end;
            }
            return false;
          });
          if (isZeroContentDeleteAttempt) {
            _document!.saveState(description: 'Backspace', forceNewAction: false);
            executeHandleBackspace(_document!);
            syncImeBufferToFragment();
            return;
          }
        }

        TextEditingValue value = currentTextEditingValue ?? const TextEditingValue();
        for (final delta in deltas) {
          // Intercept newline insertion from iOS virtual keyboard.
          // On buffer-sync platforms the OS may send the enter as a delta
          // instead of (or in addition to) performAction(newline).
          // If we apply the '\n' to the buffer and then pass it to
          // updateEditingValue, the text ends up duplicated in the new
          // paragraph because the buffer still holds the old fragment text.
          if ((delta is TextEditingDeltaInsertion && delta.textInserted.contains('\n')) ||
              (delta is TextEditingDeltaReplacement && delta.replacementText.contains('\n'))) {
            // Start grace period BEFORE the structural change so any delta
            // echo that arrives during the split is ignored.
            _structuralChangeInProgress = true;
            _structuralChangeTimer?.cancel();

            _document!.saveState(description: 'Enter', forceNewAction: true);
            executeHandleEnter(_document!);
            _justHandledEnter = true;

            // Sync the IME buffer with the NEW fragment text so the platform
            // computes subsequent deltas against the correct content. On iOS
            // this also injects the zero-width placeholder when the cursor is
            // at offset 0, preventing Backspace from being swallowed.
            _lastSyncedFragmentId = _document!.cursor.focusId.isNotEmpty
                ? _document!.cursor.focusId
                : _document!.cursor.anchorId;
            syncImeBufferToFragment();

            _structuralChangeTimer = Timer(_structuralChangeGracePeriod, () {
              _structuralChangeInProgress = false;
            });
            return;
          }

          // On macOS the physical keyboard sends a KeyEvent for backspace;
          // handling the deletion delta as well would double-delete.
          if (_isMacOS && (delta is TextEditingDeltaDeletion ||
              (delta is TextEditingDeltaReplacement &&
                  delta.replacementText.isEmpty))) {
            continue;
          }

          // Race-condition guard for rapid backspace on buffer-sync platforms
          // (iOS/Windows). When the user backspaces quickly, the platform may
          // compute this delta against its stale internal buffer (our previous
          // syncImeBufferToFragment / setEditingState hasn't been processed
          // yet). Applying such a delta to our already-updated buffer produces
          // a wrong result and causes the wrong character to be deleted.
          // Instead, detect the mismatch and call executeHandleBackspace
          // directly — the cursor is already at the correct position from the
          // previous operation, so this deletes exactly the right character.
          if (delta.oldText != value.text &&
              (delta is TextEditingDeltaDeletion ||
               (delta is TextEditingDeltaReplacement &&
                delta.replacementText.isEmpty))) {
            final deletionRange = delta is TextEditingDeltaDeletion
                ? delta.deletedRange
                : (delta as TextEditingDeltaReplacement).replacedRange;
            final deleteStart = deletionRange.start.clamp(0, delta.oldText.length);
            final deleteEnd = deletionRange.end.clamp(0, delta.oldText.length);
            final deletedText = delta.oldText.substring(deleteStart, deleteEnd);
            final graphemeCount = deletedText.characters.length;
            _document!.saveState(description: 'Backspace', forceNewAction: false);
            for (int i = 0; i < graphemeCount; i++) {
              executeHandleBackspace(_document!);
            }
            syncImeBufferToFragment();
            return;
          }

          // Handle emoji deletion on Windows: if deleting at start of surrogate pair,
          // expand deletion to include the complete emoji (2 code units)
          if (!_isMacOS && (delta is TextEditingDeltaDeletion ||
              (delta is TextEditingDeltaReplacement &&
                  delta.replacementText.isEmpty))) {
            final deletionRange = delta is TextEditingDeltaDeletion 
                ? delta.deletedRange 
                : (delta as TextEditingDeltaReplacement).replacedRange;
            
            // Check if we're deleting inside a surrogate pair (emoji)
            final deletionLength = deletionRange.end - deletionRange.start;
            if (deletionRange.isValid && deletionLength == 1) {
              final textBefore = value.text;
              final deleteStart = deletionRange.start.clamp(0, textBefore.length);
              var effectiveDeleteStart = deleteStart;
              if (deleteStart > 0 && deleteStart < textBefore.length) {
                final prev = textBefore.codeUnitAt(deleteStart - 1);
                final curr = textBefore.codeUnitAt(deleteStart);
                if (prev >= 0xD800 && prev <= 0xDBFF &&
                    curr >= 0xDC00 && curr <= 0xDFFF) {
                  // Deleting the low surrogate: expand to cover the whole pair
                  effectiveDeleteStart = deleteStart - 1;
                }
              }
              if (effectiveDeleteStart < textBefore.length) {
                final graphemeLen = FragmentOperations.getGraphemeLengthAt(textBefore, effectiveDeleteStart);
                if (graphemeLen == 2) {
                  // This is an emoji - need to delete 2 code units
                  // Adjust selection if we expanded backwards so the delta stays valid.
                  var adjustedSelection = delta.selection;
                  if (effectiveDeleteStart < deleteStart) {
                    final shift = deleteStart - effectiveDeleteStart;
                    adjustedSelection = delta.selection.copyWith(
                      baseOffset: delta.selection.baseOffset >= deleteStart
                          ? delta.selection.baseOffset - shift
                          : delta.selection.baseOffset,
                      extentOffset: delta.selection.extentOffset >= deleteStart
                          ? delta.selection.extentOffset - shift
                          : delta.selection.extentOffset,
                    );
                  }
                  // Create a modified delta with expanded range
                  if (delta is TextEditingDeltaDeletion) {
                    final expandedDelta = TextEditingDeltaDeletion(
                      oldText: delta.oldText,
                      deletedRange: TextRange(start: effectiveDeleteStart, end: effectiveDeleteStart + 2),
                      selection: adjustedSelection,
                      composing: delta.composing,
                    );
                    if (value.text != delta.oldText) {
                      value = TextEditingValue(
                        text: delta.oldText,
                        selection: delta.selection,
                        composing: delta.composing,
                      );
                    }
                    if (_isDeltaRangeValid(expandedDelta, value.text)) {
                      value = _safeApplyDelta(expandedDelta, value);
                    }
                  } else if (delta is TextEditingDeltaReplacement) {
                    final expandedDelta = TextEditingDeltaReplacement(
                      oldText: delta.oldText,
                      replacementText: '',
                      replacedRange: TextRange(start: effectiveDeleteStart, end: effectiveDeleteStart + 2),
                      selection: adjustedSelection,
                      composing: delta.composing,
                    );
                    if (value.text != delta.oldText) {
                      value = TextEditingValue(
                        text: delta.oldText,
                        selection: delta.selection,
                        composing: delta.composing,
                      );
                    }
                    if (_isDeltaRangeValid(expandedDelta, value.text)) {
                      value = _safeApplyDelta(expandedDelta, value);
                    }
                  }
                  continue;
                }
              }
            }
          }
          
          if (value.text != delta.oldText) {
            value = TextEditingValue(
              text: delta.oldText,
              selection: delta.selection,
              composing: delta.composing,
            );
          }
          if (_isDeltaRangeValid(delta, value.text)) {
            value = _safeApplyDelta(delta, value);
          } else {
            debugPrint('FluentTextInputHandler: skipping malformed delta '
                '(range exceeds oldText length ${value.text.length}): $delta');
            value = TextEditingValue(
              text: delta.oldText,
              selection: delta.selection,
              composing: delta.composing,
            );
          }
        }
        // Pass the selection offset to position cursor correctly after emoji insertion
        // If the selection would cut through a surrogate pair, use the end of text instead
        int? cursorOffset;
        if (value.selection.isValid) {
          final selOffset = value.selection.extentOffset;
          final textLen = value.text.length;
          // Check if selection is in the middle of a surrogate pair
          if (selOffset > 0 && selOffset < textLen) {
            final prev = value.text.codeUnitAt(selOffset - 1);
            final curr = value.text.codeUnitAt(selOffset);
            if (prev >= 0xD800 && prev <= 0xDBFF && curr >= 0xDC00 && curr <= 0xDFFF) {
              // Selection is in the middle of a surrogate pair, use end of text
              cursorOffset = textLen;
            } else {
              cursorOffset = selOffset;
            }
          } else {
            cursorOffset = selOffset;
          }
        }
        updateEditingValue(value, cursorOffset: cursorOffset);
        return;
      }
      
      // ─── Android & Desktop: buffer NOT synced, process deltas directly ──
      // IMPORTANT: If any delta contains a valid composing range, we should NOT
      // process the deltas here. Instead, we should let them be handled by the
      // composition branch below (line 479+) which knows how to handle preedit.
      final hasComposing = deltas.any((d) => d.composing.isValid);
      if (hasComposing) {
        // A composition is starting/active - handle via updateEditingValue
        final value = _applyDeltasSafely(
          currentTextEditingValue ?? const TextEditingValue(),
          deltas,
        );
        updateEditingValue(value);
        return;
      }
      
      final doc = _document!;
      for (final delta in deltas) {
        if (delta is TextEditingDeltaDeletion ||
            (delta is TextEditingDeltaReplacement &&
                delta.replacementText.isEmpty)) {
          // Backspace/Delete operation
          doc.saveState(description: 'Delete', forceNewAction: false);

          final deletionRange = delta is TextEditingDeltaDeletion
              ? delta.deletedRange
              : (delta as TextEditingDeltaReplacement).replacedRange;

          if (deletionRange.isValid && deletionRange.start < deletionRange.end) {
            final oldText = delta.oldText;
            final deleteStart = deletionRange.start.clamp(0, oldText.length);
            final deleteEnd = deletionRange.end.clamp(0, oldText.length);
            final deletedText = oldText.substring(deleteStart, deleteEnd);
            // executeHandleBackspace is grapheme-aware, so call it once per
            // grapheme cluster rather than per UTF-16 code unit.
            final graphemeCount = deletedText.characters.length;
            for (int i = 0; i < graphemeCount; i++) {
              executeHandleBackspace(doc);
            }
          } else if (deletionRange.isValid && deletionRange.start == deletionRange.end) {
            // Zero-length deletion on Android: the IME buffer is empty but
            // the user pressed backspace. If the cursor is on an empty
            // fragment or at the start of a fragment, treat this as a
            // structural backspace so the cursor can enter the adjacent node.
            final currentFragText = _getCurrentFragmentText() ?? '';
            if (currentFragText.isEmpty || _getCursorOffsetInFragment() == 0) {
              executeHandleBackspace(doc);
            }
          }
        } else if (delta is TextEditingDeltaNonTextUpdate) {
          // Selection or composing range changed without text mutation.
          // At this point we've already checked that composing.isValid is false
          // for all deltas, so this is just a selection change.
          // No action needed - selection changes don't affect document content.
        } else if (delta is TextEditingDeltaInsertion) {
          // Text insertion (regular character or emoji input)
          doc.saveState(description: 'Insert text', forceNewAction: false);
          final insertedText = delta.textInserted;
          _insertTextOrReplaceSelection(insertedText, doc);
        } else if (delta is TextEditingDeltaReplacement) {
          // Text replacement (selection replaced with new text)
          // This handles autocorrect, suggestion acceptance, etc.
          doc.saveState(description: 'Replace text', forceNewAction: false);
          
          final replacedRange = delta.replacedRange;
          final replacementText = delta.replacementText;
          final oldText = delta.oldText;
          
          if (replacedRange.isValid && replacedRange.start != replacedRange.end) {
            final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
            final currentOffset = doc.cursor.focusOffset;
            
            // On Android the buffer is empty before typing, so oldText contains
            // only what was typed in this session and was inserted sequentially.
            final typedGraphemeCount = oldText.characters.length;
            final bufferStartInDoc = currentOffset - typedGraphemeCount;
            
            // Convert buffer code-unit offsets to grapheme offsets
            final beforeReplace = oldText.substring(0, replacedRange.start.clamp(0, oldText.length));
            final replaceStartGraphemes = beforeReplace.characters.length;
            
            final upToReplaceEnd = oldText.substring(0, replacedRange.end.clamp(0, oldText.length));
            final replaceEndGraphemes = upToReplaceEnd.characters.length;
            
            final docStart = bufferStartInDoc + replaceStartGraphemes;
            final docEnd = bufferStartInDoc + replaceEndGraphemes;
            
            // Select the exact range to replace
            doc.cursor.batchUpdate(() {
              doc.cursor.anchorId = fragId;
              doc.cursor.anchorOffset = docStart;
              doc.cursor.focusId = fragId;
              doc.cursor.focusOffset = docEnd;
            });
            executeHandleReplaceSelection(replacementText, doc);
          } else {
            // No existing text to replace; just insert the new text
            _insertTextOrReplaceSelection(replacementText, doc);
          }
          _resetPlatformBuffer();
        }
      }
      // On Android, if deletion left the current fragment empty, reset the
      // platform buffer so the IME starts from a clean slate on the next
      // keystroke and doesn't compute deltas against stale text.
      if (!_shouldSyncBuffer) {
        final currentFragText = _getCurrentFragmentText();
        if (currentFragText != null && currentFragText.isEmpty) {
          _resetPlatformBuffer();
        }
      }
      doc.updateContent();
      return;
    }

    // Composition active: reconstruct the final TextEditingValue by
    // applying deltas sequentially against our preedit buffer, as before.
    final value = _applyDeltasSafely(
      currentTextEditingValue ?? const TextEditingValue(),
      deltas,
    );
    updateEditingValue(value);
  }

  @override
  void updateEditingValue(TextEditingValue value, {int? cursorOffset}) {
    if (_updatingSelf) return;
    if (_structuralChangeInProgress) return;
    if (_document == null) return;
    final doc = _document!;
    final cursor = doc.cursor;

    // Safety net: if the cursor points to a fragment that was removed (e.g.
    // after rapid backspace on a virtual keyboard), snap it to the nearest
    // valid caret stop so subsequent delta logic operates on a real node.
    final currentFragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    if (doc.nodeById(currentFragId) == null) {
      final fallback = moveLeft(
        doc.content,
        CaretStop(cursor.anchorId, cursor.anchorOffset),
        stops: doc.caretStops,
        cachedLines: doc.logicalLines,
      );
      if (fallback.position != null) {
        cursor.moveTo(fallback.position!.fragmentId, fallback.position!.offset);
      } else {
        final right = moveRight(
          doc.content,
          CaretStop(cursor.anchorId, cursor.anchorOffset),
          stops: doc.caretStops,
          cachedLines: doc.logicalLines,
        );
        if (right.position != null) {
          cursor.moveTo(right.position!.fragmentId, right.position!.offset);
        } else if (doc.caretStops.isNotEmpty) {
          final first = doc.caretStops.first;
          cursor.moveTo(first.fragmentId, first.offset);
        }
      }
    }

    // ─── iOS Standard IME Buffer Sync (no dummy string) ──────────
    if (_shouldSyncBuffer && !_isComposing) {
      final currentText = _getCurrentFragmentText() ?? '';
      final cursorOffset = _getCursorOffsetInFragment();

      // If the real fragment is empty, we mirrored a zero-width placeholder
      // to UIKit (see _emptyFragmentPlaceholder) so Backspace would have
      // something to act on. Pure placeholder deletion is already handled
      // earlier in updateEditingValueWithDeltas as a structural backspace,
      // so if we reach this point with the placeholder still present at the
      // very start of the incoming text, it means the user typed something
      // new into the empty paragraph (insertion/replacement) rather than
      // deleting — strip the placeholder from both sides of the comparison
      // so the rest of this method behaves exactly as if the fragment had
      // started genuinely empty.
      if (_isIOS &&
          cursorOffset == 0 &&
          value.text.startsWith(_emptyFragmentPlaceholder)) {
        final placeholderLen = _emptyFragmentPlaceholder.length;
        final strippedText = value.text.substring(placeholderLen);
        final strippedBase = (value.selection.baseOffset - placeholderLen).clamp(0, strippedText.length);
        final strippedExtent = (value.selection.extentOffset - placeholderLen).clamp(0, strippedText.length);
        final strippedComposing = value.composing.isValid
            ? TextRange(
                start: (value.composing.start - placeholderLen).clamp(0, strippedText.length),
                end: (value.composing.end - placeholderLen).clamp(0, strippedText.length),
              )
            : value.composing;
        value = TextEditingValue(
          text: strippedText,
          selection: value.selection.copyWith(
            baseOffset: strippedBase,
            extentOffset: strippedExtent,
          ),
          composing: strippedComposing,
        );
      }

      // Skip our own echo
      if (value.text == currentText &&
          value.selection.isCollapsed &&
          value.selection.extentOffset == cursorOffset) {
        // iOS virtual keyboard: when the fragment is already empty and the
        // IME sends a deletion delta on the zero-width placeholder, the
        // result is empty text with the cursor at offset 0 — exactly the
        // same signature as our own echo. We must still trigger structural
        // backspace so the empty paragraph is merged with the previous one.
        if (_isIOS && _shouldSyncBuffer && currentText.isEmpty && cursorOffset == 0) {
          doc.saveState(description: 'Backspace', forceNewAction: false);
          executeHandleBackspace(doc);
          syncImeBufferToFragment();
        }
        return;
      }

      // New composition started (CJK, emoji, etc.)
      if (value.composing.isValid) {
        // Defensive extraction to avoid cutting through surrogate pairs (emoji)
        final start = FragmentOperations.adjustIndex(value.text, value.composing.start.clamp(0, value.text.length));
        final end = FragmentOperations.adjustIndex(value.text, value.composing.end.clamp(0, value.text.length));
        final rawPreedit = value.text.substring(start, end);
        final preeditText = _sanitizeUtf16(rawPreedit);

        // Set _isComposing BEFORE clearing the selection so that
        // syncImeBufferToFragment (called via document.updateContent()
        // inside executeHandleReplaceSelection) returns early and does
        // not sync the buffer with the shorter text while the browser's
        // composition is still active. Otherwise the browser retains a
        // stale composingText and later sends a delta with an
        // out-of-bounds composing range (assertion failure in
        // TextEditingDelta.fromJSON).
        _isComposing = true;

        // When a selection is active, clear it FIRST so the fragment text
        // reflects the post-deletion state. The preedit offset must then be
        // the cursor position after clearing, not the buffer-relative
        // composing start (which is stale after the selection is removed).
        int preeditOffset;
        if (!cursor.isCollapsed) {
          final anchorNode = doc.nodeById(cursor.anchorId);
          final focusNode = doc.nodeById(cursor.focusId);
          final anchorValid = anchorNode is Fragment &&
              cursor.anchorOffset <= anchorNode.text.length;
          final focusValid = focusNode is Fragment &&
              cursor.focusOffset <= focusNode.text.length;
          if (anchorValid && focusValid) {
            doc.saveState(description: 'Replace selection', forceNewAction: false);
            executeHandleReplaceSelection('', doc);
          } else {
            if (focusValid) {
              cursor.moveTo(cursor.focusId, cursor.focusOffset);
            } else if (anchorValid) {
              cursor.moveTo(cursor.anchorId, cursor.anchorOffset);
            }
            doc.selectionManager.collapse();
          }
          // After clearing the selection the cursor is at the base of the
          // former selection — that's where the preedit should start.
          preeditOffset = cursor.focusId.isNotEmpty
              ? cursor.focusOffset
              : cursor.anchorOffset;
        } else {
          // No selection: sync fragment text to match the buffer (excluding
          // preedit) only when the buffer differs from the current fragment.
          final wholeCleanText = _sanitizeUtf16(value.text);
          final currentFragText = _getCurrentFragmentText() ?? '';
          if (wholeCleanText != currentFragText) {
            _updatingSelf = true;
            final node = doc.nodeById(cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId);
            if (node is Fragment) {
              final textBefore = wholeCleanText.substring(0, start);
              final textAfter = wholeCleanText.substring(end);
              node.text = _sanitizeUtf16(textBefore + textAfter);
            }
            _updatingSelf = false;
          }
          preeditOffset = start;
        }

        _preeditFragmentId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
        _preeditLocalOffset = preeditOffset;
        _preeditContainerId = doc.findLogicalContainerId(_preeditFragmentId) ?? '';
        cursor.imeComposing = true;
        cursor.imeComposingStart = _preeditLocalOffset;
        doc.selectionManager.clear();
        _preeditText = preeditText;
        _composingRange = TextRange(start: 0, end: preeditText.length);
        _preeditCaretOffset = value.selection.isValid
            ? (value.selection.extentOffset - start).clamp(0, preeditText.length)
            : preeditText.length;
        _invalidatePreeditRender();
        return;
      }

      final oldText = currentText;
      final newText = value.text;

      // When a selection is active, handle insertion/deletion through the
      // selection-aware path instead of the single-char paths below, which
      // would collapse the selection and insert at the wrong position.
      if (!cursor.isCollapsed) {
        if (newText != oldText) {
          String insertedText;
          if (cursor.anchorId == cursor.focusId) {
            // Single-fragment selection: use cursor offsets to precisely
            // extract the replacement text from the buffer. The text before
            // and after the selection in oldText remains unchanged in
            // newText, so we can slice it out directly.
            final selStart = cursor.anchorOffset < cursor.focusOffset
                ? cursor.anchorOffset
                : cursor.focusOffset;
            final selEnd = cursor.anchorOffset < cursor.focusOffset
                ? cursor.focusOffset
                : cursor.anchorOffset;
            final clampedStart = selStart.clamp(0, oldText.length);
            final clampedEnd = selEnd.clamp(0, oldText.length);
            final prefixLen = clampedStart;
            final suffixLen = oldText.length - clampedEnd;
            final expectedPrefix = oldText.substring(0, prefixLen);
            final expectedSuffix = oldText.substring(clampedEnd);
            final newTextPrefix = newText.length >= prefixLen
                ? newText.substring(0, prefixLen)
                : newText;
            final newTextSuffix = newText.length >= suffixLen
                ? newText.substring(newText.length - suffixLen)
                : newText;
            if (newText.length >= prefixLen + suffixLen &&
                newTextPrefix == expectedPrefix &&
                newTextSuffix == expectedSuffix) {
              insertedText = newText.substring(
                  prefixLen, newText.length - suffixLen);
            } else {
              insertedText = _computeInsertedText(oldText, newText);
            }
          } else {
            // Multi-fragment selection: fall back to diff-based extraction.
            insertedText = _computeInsertedText(oldText, newText);
          }
          doc.saveState(description: 'Replace selection', forceNewAction: false);
          if (insertedText.isNotEmpty) {
            _insertTextOrReplaceSelection(insertedText, doc);
          } else {
            executeHandleReplaceSelection('', doc);
          }
          syncImeBufferToFragment();
          doc.updateContent();
          return;
        }
      }

      // Single character insertion (including emoji which are 2 code units)
      final lengthDiff = newText.length - oldText.length;
      if (lengthDiff == 1 || lengthDiff == 2) {
        final diffIndex = _findDiffIndex(oldText, newText);
        if (diffIndex >= 0) {
          // Extract the inserted text (could be 1 or 2 code units for emoji)
          final insertedText = newText.substring(diffIndex, diffIndex + lengthDiff);
          _moveCursorToFragmentOffset(diffIndex);
          _insertFinalizedText(insertedText);
          return;
        }
      }

      // Single character deletion (including emoji which are 2 code units)
      final deleteLengthDiff = oldText.length - newText.length;
      if (deleteLengthDiff == 1 || deleteLengthDiff == 2) {
        final cursorOffset = _getCursorOffsetInFragment();
        if (cursorOffset == 0) {
          // Cursor at start of fragment: structural backspace (merge with
          // previous node) regardless of where the platform thinks the
          // deletion happened.
          doc.saveState(description: 'Backspace', forceNewAction: false);
          executeHandleBackspace(doc);
          syncImeBufferToFragment();
          return;
        }
        // Normal backspace: delete relative to the DOCUMENT cursor position,
        // not the text-diff position. The platform may have computed the
        // deletion against a stale buffer with a different cursor offset
        // (e.g. after a rapid cursor move or preceding rapid backspace).
        // Using _findDiffIndex in that case moves the cursor to the wrong
        // position and executeHandleBackspace deletes the wrong character
        // — typically the one right after the intended cursor position.
        doc.saveState(description: 'Backspace', forceNewAction: false);
        if (deleteLengthDiff == 2) {
          // Could be an emoji (1 grapheme = 2 code units) or two separate
          // characters batched into one delta (rapid double backspace).
          // executeHandleBackspace is grapheme-aware, so one call handles
          // emoji. For two separate characters, call it twice.
          final diffIndex = _findDiffIndex(newText, oldText);
          if (diffIndex >= 0) {
            final deletedText = oldText.substring(diffIndex, diffIndex + 2);
            final graphemeCount = deletedText.characters.length;
            for (int i = 0; i < graphemeCount; i++) {
              executeHandleBackspace(doc);
            }
          } else {
            executeHandleBackspace(doc);
          }
        } else {
          executeHandleBackspace(doc);
        }
        syncImeBufferToFragment();
        return;
      }

      // Text replacement (suggestion, paste, etc.)
      if (newText != oldText) {
        // When the replacement completely empties the fragment (common on
        // iOS virtual keyboard when the user holds backspace), we must not
        // leave a zombie empty fragment that traps the cursor. Empty the
        // fragment and let the structural backspace path handle container
        // merging just like the physical keyboard does.
        if (newText.isEmpty && oldText.isNotEmpty) {
          final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
          final node = doc.nodeById(fragId);
          if (node is Fragment) {
            doc.saveState(description: 'Backspace', forceNewAction: false);
            node.text = '';
            doc.cursor.moveTo(fragId, 0);
            doc.updateContent();
            executeHandleBackspace(doc);
            syncImeBufferToFragment();
            return;
          }
        }
        // If there's an active document selection, replace it with the
        // inserted text instead of overwriting the entire fragment.
        // This correctly handles multi-node selections, matching the
        // physical-keyboard path in EventHandler.handleCharacterInput.
        if (!cursor.isCollapsed) {
          final insertedText = _computeInsertedText(oldText, newText);
          doc.saveState(description: 'Replace selection', forceNewAction: false);
          _insertTextOrReplaceSelection(insertedText, doc);
          syncImeBufferToFragment();
          doc.updateContent();
          return;
        }
        _replaceFragmentText(newText, cursorOffset: cursorOffset);
        return;
      }

      // Cursor moved without text change
      if (newText == oldText && value.selection.isValid && value.selection.isCollapsed) {
        _moveCursorToFragmentOffset(value.selection.extentOffset);
        return;
      }

      return;
    }

    // ─── Active composition handling ────────────────────────────────
    if (_isComposing) {
      if (value.composing.isValid) {
        // Composition shrank (backspace inside the preedit on iOS).
        if (value.text.isEmpty) {
          // Preedit fully erased. The preedit lives isolated from the
          // document, so cancelling it removes exactly the characters the
          // user typed — we must NOT also backspace the document, otherwise
          // the committed character before the preedit gets deleted too.
          _cancelPreedit();
          return;
        }
        // Still has preedit content: extract it from the full buffer.
        if (_shouldSyncBuffer) {
          final start = FragmentOperations.adjustIndex(value.text, value.composing.start.clamp(0, value.text.length));
          final end = FragmentOperations.adjustIndex(value.text, value.composing.end.clamp(0, value.text.length));
          final rawPreedit = value.text.substring(start, end);
          final preeditText = _sanitizeUtf16(rawPreedit);
          _preeditText = preeditText;
          _composingRange = TextRange(start: 0, end: preeditText.length);
          _preeditCaretOffset = value.selection.isValid
              ? (value.selection.extentOffset - start).clamp(0, preeditText.length)
              : preeditText.length;
        } else {
          final start = value.composing.start.clamp(0, value.text.length);
          final end = value.composing.end.clamp(0, value.text.length);
          final rawPreedit = value.text.substring(start, end);
          final preeditText = _sanitizeUtf16(rawPreedit);
          _preeditText = preeditText;
          _composingRange = TextRange(start: 0, end: preeditText.length);
          _preeditCaretOffset = value.selection.isValid
              ? (value.selection.extentOffset - start).clamp(0, preeditText.length)
              : preeditText.length;
        }
        _invalidatePreeditRender();
        return;
      }

      // Composing became invalid (text confirmed / space pressed).
      if (value.text == _preeditText) {
        // Spurious echo, keep composing
        return;
      }

      if (value.text.isEmpty) {
        // Preedit became empty - the last preedit character was erased.
        // Only cancel the preedit; do NOT backspace the document (the
        // preedit was never committed, so there is nothing extra to delete).
        _cancelPreedit();
        return;
      }

      if (_shouldSyncBuffer) {
        // Buffer-sync commit: the full buffer already contains the
        // committed text merged with the surrounding fragment text.
        final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
        final node = doc.nodeById(fragId);
        if (node is Fragment) {
          _updatingSelf = true; // Block platform echoes during document mutation

          doc.saveState(description: 'Replace text', forceNewAction: false);

          // FIX macOS: When the committed text is shorter than the previous
          // preedit, we must explicitly clear the old preedit from the editor
          // before applying the final buffer string to avoid ghost fragments.
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
            final oldText = node.text;
            final preeditLen = _preeditText.length;
            final startOffset = _preeditLocalOffset.clamp(0, oldText.length);

            // If the previous composition occupied space, remove it cleanly
            if (preeditLen > 0 && startOffset + preeditLen <= oldText.length) {
              node.text = oldText.substring(0, startOffset) + oldText.substring(startOffset + preeditLen);
            }
          }

          // Reconstruct the fragment text by inserting the committed text
          // at _preeditLocalOffset. We cannot use value.text directly
          // because on web the browser's buffer may still contain stale
          // text from before the selection was cleared (we skip
          // syncImeBufferToFragment during composition to avoid disrupting
          // the platform's composition state). On iOS, value.text can also
          // be stale/hybrid.
          //
          // The committed text is extracted from value.text by removing the
          // fragment's prefix and suffix around the preedit position. This
          // handles both stale selection text (browser didn't update the
          // buffer after selection clearing) and predictive text correction
          // (committed text differs from the last preedit).
          final currentFragText = node.text;
          final insertOffset = _preeditLocalOffset.clamp(0, currentFragText.length);
          final prefix = currentFragText.substring(0, insertOffset);
          final suffix = currentFragText.substring(insertOffset);
          String committedText;
          if (value.text.length >= prefix.length + suffix.length &&
              value.text.startsWith(prefix) &&
              value.text.endsWith(suffix)) {
            committedText = _sanitizeUtf16(
              value.text.substring(prefix.length, value.text.length - suffix.length),
            );
          } else {
            // Fallback: use _preeditText if value.text doesn't match the
            // expected structure (e.g., iOS stale buffer).
            committedText = _sanitizeUtf16(_preeditText);
          }
          node.text = _sanitizeUtf16(prefix + committedText + suffix);
          final newCursorOffset = insertOffset + committedText.length;
          doc.cursor.moveTo(fragId, newCursorOffset);
          _resetComposition();
          doc.cursor.imeComposing = false;
          doc.updateContent();

          _updatingSelf = false; // Unblock after document is updated

          syncImeBufferToFragment(); // Now safe to sync
        }
        return;
      }

      // ─── Android: Composition confirmation ──────────────────────
      // IMPORTANT: On Android, the buffer is NOT synced with the document.
      // When composition ends, value.text contains the finalized text (e.g., CJK ideograph).
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // If the buffer text has changed from the previous preedit, it means
        // the user selected a replacement suggestion (e.g. CJK).
        final finalizedText = value.text.isNotEmpty ? value.text : _preeditText;
        _commitPreedit(finalizedText);
      } else {
        _commitPreedit(_preeditText);
      }

      _resetPlatformBuffer();
      return;
    }

    // ─── New composition start ────────────────────────────────────
    if (value.text.isEmpty) return;

    if (!value.composing.isValid) {
      // Caso 4: Testo confermato senza composizione
      _insertFinalizedText(value.text);
      if (_shouldSyncBuffer) {
        syncImeBufferToFragment();
      } else {
        _resetPlatformBuffer();
      }
      return;
    }

    // Set _isComposing BEFORE clearing the selection so that
    // syncImeBufferToFragment (called via document.updateContent()
    // inside executeHandleReplaceSelection) returns early and does
    // not sync the buffer with the shorter text while the browser's
    // composition is still active.
    _isComposing = true;

    // Start new composition
    if (!cursor.isCollapsed) {
      // Guard against stale cursor offsets (see the same guard in the
      // buffer-sync composition-start path above).
      final anchorNode = doc.nodeById(cursor.anchorId);
      final focusNode = doc.nodeById(cursor.focusId);
      final anchorValid = anchorNode is Fragment &&
          cursor.anchorOffset <= anchorNode.text.length;
      final focusValid = focusNode is Fragment &&
          cursor.focusOffset <= focusNode.text.length;
      if (anchorValid && focusValid) {
        doc.saveState(description: 'Replace selection', forceNewAction: false);
        executeHandleReplaceSelection('', doc);
      } else {
        if (focusValid) {
          cursor.moveTo(cursor.focusId, cursor.focusOffset);
        } else if (anchorValid) {
          cursor.moveTo(cursor.anchorId, cursor.anchorOffset);
        }
        doc.selectionManager.collapse();
      }
    }

    _preeditFragmentId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    _preeditLocalOffset = cursor.focusId.isNotEmpty ? cursor.focusOffset : cursor.anchorOffset;
    _preeditContainerId = doc.findLogicalContainerId(_preeditFragmentId) ?? '';
    cursor.imeComposing = true;
    cursor.imeComposingStart = _preeditLocalOffset;
    doc.selectionManager.clear();
    final compStart = value.composing.start.clamp(0, value.text.length);
    final compEnd = value.composing.end.clamp(0, value.text.length);
    final rawPreedit = value.text.substring(compStart, compEnd);
    final preeditText = _sanitizeUtf16(rawPreedit);
    _preeditText = preeditText;
    _composingRange = TextRange(start: 0, end: preeditText.length);
    _preeditCaretOffset = value.selection.isValid
        ? (value.selection.extentOffset - compStart).clamp(0, preeditText.length)
        : preeditText.length;
    _invalidatePreeditRender();
  }

  @override
  void performAction(TextInputAction action) {
    if (_document == null) return;
    switch (action) {
      case TextInputAction.newline:
        // If the newline was already handled via delta (iOS virtual
        // keyboard often sends both a delta and a performAction),
        // skip the second enter to avoid double-splitting.
        if (_justHandledEnter) {
          _justHandledEnter = false;
          break;
        }

        // Start grace period BEFORE the structural change so any platform
        // echo that arrives during the split is ignored.
        _structuralChangeInProgress = true;
        _structuralChangeTimer?.cancel();

        // Commit any pending preedit first, then handle enter.
        commitIfComposing();
        _document!.saveState(description: 'Enter', forceNewAction: true);
        executeHandleEnter(_document!);

        // Sync the IME buffer with the NEW fragment text so the platform
        // computes subsequent deltas against the correct content. On iOS
        // this also injects the zero-width placeholder when the cursor is
        // at offset 0, preventing Backspace from being swallowed.
        _lastSyncedFragmentId = _document!.cursor.focusId.isNotEmpty
            ? _document!.cursor.focusId
            : _document!.cursor.anchorId;
        syncImeBufferToFragment();

        _structuralChangeTimer = Timer(_structuralChangeGracePeriod, () {
          _structuralChangeInProgress = false;
        });
        break;
      case TextInputAction.go:
      case TextInputAction.send:
      case TextInputAction.done:
        commitIfComposing();
        break;
      default:
        break;
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // No-op for now.
  }

  @override
  bool onFocusReceived() {
    // Returning false keeps the platform's default behavior (it will still
    // proceed to show the keyboard via showKeyboard()/show() as we already
    // drive that ourselves). We don't need custom focus-acquisition logic
    // here, but the override is mandatory on Flutter versions where
    // TextInputClient declares it without a default mixin implementation.
    return false;
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // No-op.
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // No-op.
  }

  @override
  void connectionClosed() {
    commitIfComposing();
    _connection = null;
  }

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
    // No-op.
  }

  @override
  void insertContent(KeyboardInsertedContent content) {
    // No-op.
  }

  @override
  void insertTextPlaceholder(Size size) {
    // No-op.
  }

  @override
  void performSelector(String selectorName) {
    // No-op.
  }

  @override
  void removeTextPlaceholder() {
    // No-op.
  }

  @override
  void showToolbar() {
    // No-op.
  }

  // ─── Preedit lifecycle ──────────────────────────────────────────

  /// Commits any active preedit into the document. Safe to call even when
  /// no composition is active. Used on focus loss, connection close, enter
  /// key, send/done actions, etc.
  void commitIfComposing() {
    if (_isComposing && _preeditText.isNotEmpty) {
      _commitPreedit(_preeditText);
    } else if (_isComposing) {
      _cancelPreedit();
    }
  }

  /// Centralized text insertion logic shared by all IME code paths.
  ///
  /// If the document has an active (non-collapsed) selection, the first
  /// grapheme replaces the selection via [executeHandleReplaceSelection]
  /// (which correctly handles multi-node selections). Subsequent graphemes
  /// are inserted via [executeHandleInsertCharacter] since the selection
  /// is collapsed after the first call.
  ///
  /// This mirrors the physical-keyboard pattern in [EventHandler.handleCharacterInput]
  /// and ensures the virtual keyboard behaves identically.
  void _insertTextOrReplaceSelection(String text, FluentDocument doc) {
    for (final char in text.characters) {
      if (!doc.cursor.isCollapsed) {
        executeHandleReplaceSelection(char, doc);
      } else {
        executeHandleInsertCharacter(char, doc);
      }
    }
  }

  /// Computes the net inserted text by diffing [oldText] and [newText].
  ///
  /// Finds the common prefix and suffix, then returns the middle portion of
  /// [newText] — i.e. the text that was actually added by the IME. If text
  /// was only removed (no addition), returns an empty string.
  String _computeInsertedText(String oldText, String newText) {
    if (oldText.isEmpty) return newText;
    if (newText.isEmpty) return '';

    int prefixLen = 0;
    final minLen = oldText.length < newText.length ? oldText.length : newText.length;
    while (prefixLen < minLen && oldText[prefixLen] == newText[prefixLen]) {
      prefixLen++;
    }

    int suffixLen = 0;
    while (suffixLen < oldText.length - prefixLen &&
        suffixLen < newText.length - prefixLen &&
        oldText[oldText.length - 1 - suffixLen] ==
            newText[newText.length - 1 - suffixLen]) {
      suffixLen++;
    }

    return newText.substring(prefixLen, newText.length - suffixLen);
  }

  /// Inserts text that the platform reported as already finalized (no
  /// composing range at all), bypassing the preedit buffer entirely.
  void _insertFinalizedText(String text) {
    if (_document == null || text.isEmpty) return;
    final doc = _document!;

    doc.saveState(description: 'Insert text', forceNewAction: false);

    _insertTextOrReplaceSelection(text, doc);

    if (_shouldSyncBuffer) {
      syncImeBufferToFragment();
    } else {
      _resetPlatformBuffer();
    }
    doc.updateContent();
  }

  /// Commits the preedit text into the document at the stored cursor position.
  void _commitPreedit(String text) {
    if (_document == null || text.isEmpty) {
      _cancelPreedit();
      return;
    }
    final doc = _document!;

    _updatingSelf = true; // Block platform echoes during character-by-character insertion

    // Save state once for the whole commit so undo removes the entire
    // committed word/phrase in one step, not character by character.
    doc.saveState(description: 'IME commit', forceNewAction: false);

    // Unlock the cursor so insertions advance normally.
    doc.cursor.imeComposing = false;

    // Move cursor back to the original composition start before inserting.
    doc.cursor.moveTo(_preeditFragmentId, _preeditLocalOffset);

    // Insert the committed text using the centralized handler so pending
    // font/styles are respected and selection replacement works correctly.
    _insertTextOrReplaceSelection(text, doc);

    _resetComposition();
    
    _updatingSelf = false; // Unblock after all characters are inserted
    
    if (_shouldSyncBuffer) {
      syncImeBufferToFragment();
    } else {
      _resetPlatformBuffer();
    }
    doc.updateContent();
  }

  /// Cancels the active composition without mutating the document.
  void _cancelPreedit() {
    final doc = _document;
    _resetComposition();
    if (doc != null) {
      doc.cursor.imeComposing = false;
      if (_shouldSyncBuffer) {
        syncImeBufferToFragment();
      } else {
        _resetPlatformBuffer();
      }
      // Trigger a cursor-only repaint so the preedit underline disappears.
      doc.cursorOnlyUpdate();
    }
  }

  /// Resets the platform-side IME buffer to empty after we've applied text
  /// to the document ourselves. This prevents the IME from re-sending the
  /// just-committed text as a fresh "new composition" on the next keystroke,
  /// and guards against the platform echoing our own mutation back to us.
  void _resetPlatformBuffer() {
    if (_connection == null || !_connection!.attached) return;
    _updatingSelf = true;
    try {
      _connection!.setEditingState(const TextEditingValue());
      _lastSyncedText = '';
    } on PlatformException catch (e) {
      debugPrint('FluentTextInputHandler: _resetPlatformBuffer failed: ${e.message}');
    }
    _updatingSelf = false;
  }

  void _resetComposition() {
    _isComposing = false;
    _preeditText = '';
    _composingRange = TextRange.empty;
    _preeditFragmentId = '';
    _preeditLocalOffset = 0;
    _preeditContainerId = '';
    _preeditCaretOffset = 0;
  }

  /// Handles composing range changes on Android when composition starts/changes.
  /// Called when the platform reports a new composing range without text change.
  void _handleComposingRangeChange(TextRange composing, int cursorOffset) {
    if (!composing.isValid) {
      if (_isComposing) {
        // Composition ended
        _cancelPreedit();
      }
      return;
    }

    // Composition range is valid
    if (!_isComposing) {
      // Starting new composition: lock cursor to current fragment
      final doc = _document;
      if (doc == null) return;

      final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
      _preeditFragmentId = fragId;
      _preeditLocalOffset = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusOffset : doc.cursor.anchorOffset;
      _preeditContainerId = doc.findLogicalContainerId(_preeditFragmentId) ?? '';

      doc.cursor.imeComposing = true;
      _isComposing = true;
      _preeditText = '';
      _composingRange = TextRange.empty;
    }

    // Update composing range
    _composingRange = composing;
    _preeditCaretOffset = cursorOffset;

    _invalidatePreeditRender();
  }

  /// On buffer-sync platforms (iOS) UIKit treats a completely empty text
  /// buffer as having nothing for Backspace to act on: pressing Backspace
  /// while `text: ''` produces NO callback whatsoever (no delta, no
  /// KeyEvent) — the keystroke is silently swallowed by UIKit itself before
  /// it ever reaches Flutter. This breaks Backspace at the start of an
  /// empty paragraph, since the current fragment's text is '' and that is
  /// exactly what we hand to setEditingState.
  ///
  /// To give UIKit something to delete, we mirror a single zero-width space
  /// in the platform buffer whenever the real fragment text is empty. This
  /// placeholder NEVER touches the document model (node.text stays '') —
  /// it exists purely in the platform's copy of the text so Backspace
  /// generates a real, observable delta we can intercept and translate into
  /// a structural backspace (merge with the previous node).
  static const String _emptyFragmentPlaceholder = '\u200B';

  /// Returns the text of the fragment where the cursor currently sits.
  String? _getCurrentFragmentText() {
    final doc = _document;
    if (doc == null) return null;
    final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
    final node = doc.nodeById(fragId);
    if (node is Fragment) return node.text;
    return null;
  }

  /// Returns the cursor offset within the current fragment text.
  int _getCursorOffsetInFragment() {
    final doc = _document;
    if (doc == null) return 0;
    return doc.cursor.focusId.isNotEmpty ? doc.cursor.focusOffset : doc.cursor.anchorOffset;
  }

  /// True when the cursor is at the very start of the current fragment.
  /// On buffer-sync platforms (iOS virtual keyboard) the IME has no text
  /// before the cursor in its internal buffer, so a backspace will not emit
  /// a deletion delta and must be handled structurally by the editor.
  bool get cursorIsAtFragmentStart => _getCursorOffsetInFragment() == 0;

  /// Finds the first index where [a] and [b] differ. Returns -1 if identical.
  int _findDiffIndex(String a, String b) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      if (a[i] != b[i]) return i;
    }
    if (a.length != b.length) return minLen;
    return -1;
  }

  /// Moves the cursor to the given [offset] within the current fragment.
  void _moveCursorToFragmentOffset(int offset) {
    final doc = _document;
    if (doc == null) return;
    final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
    doc.cursor.moveTo(fragId, offset);
  }

  /// Replaces the entire text of the current fragment with [newText].
  /// If [cursorOffset] is provided, positions the cursor at that offset instead of at the end.
  void _replaceFragmentText(String newText, {int? cursorOffset}) {
    final doc = _document;
    if (doc == null) return;
    final fragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;
    final node = doc.nodeById(fragId);
    if (node is! Fragment) return;

    doc.saveState(description: 'Replace text', forceNewAction: false);
    
    final cleanText = _sanitizeUtf16(newText);
    node.text = cleanText;
    final finalOffset = cursorOffset ?? cleanText.length;
    doc.cursor.moveTo(fragId, finalOffset);
    doc.updateContent();
    syncImeBufferToFragment();
  }

  /// Syncs the platform IME buffer with the current fragment text and cursor.
  /// Call after any document mutation or cursor move.
  void syncImeBufferToFragment() {
    if (_connection == null || !_connection!.attached) return;
    if (_isComposing) return;

    final doc = _document;
    if (doc == null) return;
    final currentFragId = doc.cursor.focusId.isNotEmpty ? doc.cursor.focusId : doc.cursor.anchorId;

    if (!_shouldSyncBuffer) {
      // Android: only reset the buffer when the cursor moves to a different
      // fragment. If we're still in the same fragment, leave the buffer alone
      // so the IME can keep its suggestion context.
      if (currentFragId != _lastSyncedFragmentId) {
        _resetPlatformBuffer();
      }
      _lastSyncedFragmentId = currentFragId;
      return;
    }

    _lastSyncedFragmentId = currentFragId;
    final text = _getCurrentFragmentText();
    if (text == null) return;
    final cursor = doc.cursor;
    final isSingleFragSelection =
        !cursor.isCollapsed && cursor.anchorId == cursor.focusId;
    final offset = _getCursorOffsetInFragment();
    final bool usePlaceholder = _isIOS &&
        cursor.isCollapsed &&
        offset == 0 &&
        !text.startsWith(_emptyFragmentPlaceholder);
    final syncedText = usePlaceholder ? '$_emptyFragmentPlaceholder$text' : text;
    final syncedOffset = usePlaceholder ? 1 : offset.clamp(0, syncedText.length);
    final TextSelection syncedSelection;
    if (isSingleFragSelection && !usePlaceholder) {
      syncedSelection = TextSelection(
        baseOffset: cursor.anchorOffset.clamp(0, syncedText.length),
        extentOffset: cursor.focusOffset.clamp(0, syncedText.length),
      );
    } else {
      syncedSelection = TextSelection.collapsed(offset: syncedOffset);
    }
    final currentSelectionKey =
        '${cursor.anchorId}:${cursor.anchorOffset}:${cursor.focusId}:${cursor.focusOffset}';
    final bool selectionChanged = currentSelectionKey != _prevSelectionKey;
    _prevSelectionKey = currentSelectionKey;

    _updatingSelf = true;
    try {
      // On web, if the new text is shorter than what the browser currently
      // holds, the browser sends a delta with a stale composing range that
      // exceeds the new text length, triggering an assertion in
      // TextEditingDelta.fromJSON. Resetting to empty first (same approach
      // as iOS) forces the browser to treat the next setEditingState as a
      // fresh insertion with no stale composition state.
      if (kIsWeb && syncedText.length < _lastSyncedText.length) {
        _connection!.setEditingState(const TextEditingValue());
      }
      if (_isIOS && selectionChanged) {
        _connection!.setEditingState(const TextEditingValue());
      }
      _connection!.setEditingState(TextEditingValue(
        text: syncedText,
        selection: syncedSelection,
        composing: TextRange.empty,
      ));
      _lastSyncedText = syncedText;
    } on PlatformException catch (e) {
      debugPrint('FluentTextInputHandler: syncImeBufferToFragment failed: ${e.message}');
    }
    _updatingSelf = false;
    // On web, reposition the hidden <textarea> so the IME popup follows
    // the cursor after the buffer content changed (e.g. after accepting a
    // suggestion). Without this the popup stays at the old position.
    if (kIsWeb) {
      _updateWebImePosition();
    }
  }

  /// Invalidates paint on the paragraph render that hosts the preedit.
  void _invalidatePreeditRender() {
    if (_document == null || _preeditContainerId.isEmpty) {
      return;
    }
    final doc = _document!;
    final render = doc.paragraphRegistry.renderFor(_preeditContainerId);
    if (render != null) {
      render.imePreeditText = _preeditText;
      render.imeComposingRange = _composingRange;
      render.imePreeditFragmentId = _preeditFragmentId;
      render.imePreeditLocalOffset = _preeditLocalOffset;
      render.markNeedsPaint();
      // Update the caret rect so the IME candidate window follows the caret
      // inside the marked text. Deferred to post-frame because setting the
      // preedit text triggers markNeedsLayout: the painter must re-layout with
      // the new preedit before we can query the caret position.
      final caretOffset = _preeditCaretOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isComposing) return;
        final rect = render.getImePreeditCaretScreenRect(caretOffset);
        if (rect != null) {
          // The FlutterView on macOS is flipped (top-left origin).
          // convertRect:toView:nil already handles top-left → bottom-left.
          updateCaretRect(rect);
        }
      });
    }
  }

  /// Sanitizes a string to ensure it's well-formed UTF-16.
  /// Replaces orphaned surrogate pairs with the Unicode replacement character (U+FFFD).
  /// This prevents painting library crashes when malformed strings reach the native renderer.
  String _sanitizeUtf16(String s) {
    if (s.isEmpty) return s;
    final codeUnits = s.codeUnits;
    final cleanUnits = <int>[];

    for (int i = 0; i < codeUnits.length; i++) {
      int unit = codeUnits[i];
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        // High surrogate: must be followed by a valid low surrogate
        if (i + 1 < codeUnits.length && codeUnits[i + 1] >= 0xDC00 && codeUnits[i + 1] <= 0xDFFF) {
          cleanUnits.add(unit);
          cleanUnits.add(codeUnits[i + 1]);
          i++; // Skip the low surrogate we just paired
        } else {
          // Orphaned high surrogate (malformed), replace it
          cleanUnits.add(0xFFFD);
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        // Orphaned low surrogate (malformed)
        cleanUnits.add(0xFFFD);
      } else {
        // Standard well-formed character
        cleanUnits.add(unit);
      }
    }
    return String.fromCharCodes(cleanUnits);
  }

  /// Returns true if the given container id is the one hosting the active preedit.
  bool isPreeditInContainer(String containerId) {
    return _isComposing && _preeditContainerId == containerId;
  }
}