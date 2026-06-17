import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_insert_character.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/handlers/handle_enter.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';

/// Singleton IME handler that implements [TextInputClient] for Flutter's
/// system text input channel. Preedit text is kept isolated from the document
/// model and only committed when the composition genuinely ends.
class FluentTextInputHandler with DeltaTextInputClient {
  static final FluentTextInputHandler _instance = FluentTextInputHandler._internal();
  factory FluentTextInputHandler() => _instance;
  FluentTextInputHandler._internal();

  TextInputConnection? _connection;
  FluentDocument? _document;

  /// iOS is the only platform where the on-screen keyboard backspace does not
  /// surface as a hardware KeyEvent and does not reliably emit deletion deltas
  /// against an empty buffer. The dummy-string workaround is therefore scoped
  /// to iOS only, so desktop (which deletes via EventHandler/KeyEvent) and
  /// Android (which emits proper deltas) are left untouched.
  bool get _useDummyStringWorkaround =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

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

  /// Whether the platform TextInput connection is currently open.
  bool get isConnectionActive => _connection != null && _connection!.attached;

  /// Last known caret rect (Flutter view logical coordinates).
  Rect? _lastCaretRect;

  /// Last known Flutter view height in logical pixels.
  double? _lastViewHeight;

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
    _connection!.setEditableSizeAndTransform(
      const Size(9999, 9999),
      Matrix4.identity(),
    );
  }

  /// Updates the caret rectangle so the platform can position the IME
  /// candidate window (e.g. NSTextInputContext on macOS) near the cursor.
  /// [rect] must be in Flutter view logical pixel coordinates.
  void updateCaretRect(Rect rect) {
    _lastCaretRect = rect;
    if (_connection == null || !_connection!.attached) return;
    _connection!.setCaretRect(rect);
    _connection!.setComposingRect(rect);
  }

  /// Attaches the IME connection to the given document.
  void attachInput(FluentDocument document) {
    _document = document;
  }

  /// Detaches and closes the IME connection.
  void detachInput() {
    commitIfComposing();
    _connection?.close();
    _connection = null;
    _document = null;
    _resetComposition();
  }

  /// Opens the keyboard (requests focus from the platform text input).
  void showKeyboard() {
    if (_connection == null || !_connection!.attached) {
      _attachConnection();
    }
    _connection?.show();
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

  void _attachConnection() {
    if (_document == null) return;
    _connection = TextInput.attach(
      this,
      const TextInputConfiguration(
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
      ),
    );
    // Initialise the IME with an EMPTY buffer (not whatever stale preedit
    // state we might be holding). The platform's own composition buffer is
    // always considered the source of truth for what's "in progress"; our
    // _preeditText only mirrors it for rendering purposes.
    _connection!.setEditingState(const TextEditingValue());
    _connection!.show();
  }

  // ─── TextInputClient implementation ─────────────────────────────

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    if (_isComposing) {
      return TextEditingValue(
        text: _preeditText,
        selection: TextSelection.collapsed(offset: _preeditText.length),
        composing: _composingRange,
      );
    }
    // iOS dummy string workaround: keep a single space in the IME buffer
    // when not composing so the on-screen keyboard always has something to
    // delete, allowing backspace to surface as a deletion delta.
    if (_useDummyStringWorkaround) {
      return const TextEditingValue(
        text: ' ',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange.empty,
      );
    }
    // Other platforms keep an empty buffer (backspace handled via KeyEvent).
    return const TextEditingValue();
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (_updatingSelf) return;
    if (_document == null) return;

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
    //
    // iOS: when not composing we keep a dummy " " in the IME buffer so the
    // platform always has something to delete. A backspace on already
    // committed document text arrives here as a TextEditingDeltaDeletion
    // (or an empty TextEditingDeltaReplacement) that removes the dummy
    // space. Because iOS does NOT emit a hardware KeyEvent for the virtual
    // keyboard, we MUST apply the deletion to the real document here and
    // then re-arm the dummy string for the next backspace.
    if (!_isComposing) {
      final doc = _document!;
      for (final delta in deltas) {
        if (delta is TextEditingDeltaDeletion ||
            (delta is TextEditingDeltaReplacement &&
                delta.replacementText.isEmpty)) {
          // Deletion of the dummy buffer => backspace on the document.
          // Only on iOS: other platforms delete via KeyEvent/EventHandler,
          // so applying it here too would double-delete.
          if (_useDummyStringWorkaround) {
            doc.saveState(description: 'Backspace', forceNewAction: false);
            executeHandleBackspace(doc);
            _resetToDummyString();
          }
          return;
        } else if (delta is TextEditingDeltaNonTextUpdate) {
          // Selection/composing-only update with no text change: ignore.
          continue;
        } else {
          // Insertion or non-empty replacement delta with no active
          // composition: fall through to the normal value-based path below
          // for this and any remaining deltas.
          TextEditingValue value = currentTextEditingValue ?? const TextEditingValue();
          for (final d in deltas) {
            value = d.apply(value);
          }
          updateEditingValue(value);
          return;
        }
      }
      return;
    }

    // Composition active: reconstruct the final TextEditingValue by
    // applying deltas sequentially against our preedit buffer, as before.
    TextEditingValue value = currentTextEditingValue ?? const TextEditingValue();
    for (final delta in deltas) {
      value = delta.apply(value);
    }
    updateEditingValue(value);
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    if (_updatingSelf) return;
    if (_document == null) return;

    final doc = _document!;
    final cursor = doc.cursor;

    // ─── iOS Dummy String Workaround ───────────────────────────────
    if (_useDummyStringWorkaround) {
      // Resting state: the dummy " " sitting in the buffer. Nothing to do.
      if (value.text == ' ' && !value.composing.isValid) {
        return;
      }

      // Backspace consumed the dummy " " (or the document is already empty)
      // with no active composition => delete one character from the document
      // and re-arm the dummy buffer for the next backspace.
      if (value.text.isEmpty && !_isComposing) {
        doc.saveState(description: 'Backspace', forceNewAction: false);
        executeHandleBackspace(doc);
        _resetToDummyString();
        return;
      }
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
          _resetToDummyString();
          return;
        }
        // Still has preedit content: just shrink the underline.
        _preeditText = value.text;
        _composingRange = value.composing;
        _preeditCaretOffset = value.selection.isValid
            ? value.selection.extentOffset.clamp(0, value.text.length)
            : value.text.length;
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
        _resetToDummyString();
        return;
      }

      _commitPreedit(value.text);
      _resetToDummyString();
      return;
    }

    // ─── New composition start ────────────────────────────────────
    if (value.text.isEmpty) return;

    if (!value.composing.isValid) {
      // Caso 4: Testo confermato senza composizione
      _insertFinalizedText(value.text);
      _resetToDummyString();
      return;
    }

    // Start new composition
    if (!cursor.isCollapsed) {
      doc.saveState(description: 'Replace selection', forceNewAction: false);
      executeHandleReplaceSelection('', doc);
    }

    _isComposing = true;
    _preeditFragmentId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    _preeditLocalOffset = cursor.focusId.isNotEmpty ? cursor.focusOffset : cursor.anchorOffset;
    _preeditContainerId = doc.findLogicalContainerId(_preeditFragmentId) ?? '';
    cursor.imeComposing = true;
    cursor.imeComposingStart = _preeditLocalOffset;
    doc.selectionManager.clear();
    _preeditText = value.text;
    _composingRange = value.composing;
    _preeditCaretOffset = value.selection.isValid
        ? value.selection.extentOffset.clamp(0, value.text.length)
        : value.text.length;
    _invalidatePreeditRender();
  }

  /// Re-arm the platform IME buffer after applying text to the document.
  /// On iOS this installs the dummy " " so the next backspace produces a
  /// deletion delta; on every other platform it resets to an empty buffer
  /// (the long-standing behavior, backspace handled via KeyEvent).
  void _resetToDummyString() {
    if (_connection == null || !_connection!.attached) return;
    _updatingSelf = true;
    _connection!.setEditingState(
      _useDummyStringWorkaround
          ? const TextEditingValue(
              text: ' ',
              selection: TextSelection.collapsed(offset: 1),
              composing: TextRange.empty,
            )
          : const TextEditingValue(),
    );
    _updatingSelf = false;
  }

  @override
  void performAction(TextInputAction action) {
    if (_document == null) return;
    switch (action) {
      case TextInputAction.newline:
        // Commit any pending preedit first, then handle enter.
        commitIfComposing();
        _document!.saveState(description: 'Enter', forceNewAction: true);
        executeHandleEnter(_document!);
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

  /// Inserts text that the platform reported as already finalized (no
  /// composing range at all), bypassing the preedit buffer entirely.
  void _insertFinalizedText(String text) {
    if (_document == null || text.isEmpty) return;
    final doc = _document!;

    doc.saveState(description: 'Insert text', forceNewAction: false);

    for (final char in text.characters) {
      if (!doc.cursor.isCollapsed) {
        executeHandleReplaceSelection(char, doc);
      } else {
        executeHandleInsertCharacter(char, doc);
      }
    }

    _resetPlatformBuffer();
    doc.updateContent();
  }

  /// Commits the preedit text into the document at the stored cursor position.
  void _commitPreedit(String text) {
    if (_document == null || text.isEmpty) {
      _cancelPreedit();
      return;
    }
    final doc = _document!;

    // Save state once for the whole commit so undo removes the entire
    // committed word/phrase in one step, not character by character.
    doc.saveState(description: 'IME commit', forceNewAction: false);

    // Unlock the cursor so insertions advance normally.
    doc.cursor.imeComposing = false;

    // Move cursor back to the original composition start before inserting.
    doc.cursor.moveTo(_preeditFragmentId, _preeditLocalOffset);

    // Insert the committed text character by character using the existing
    // handlers so pending font/styles are respected.
    for (final char in text.characters) {
      if (!doc.cursor.isCollapsed) {
        executeHandleReplaceSelection(char, doc);
      } else {
        executeHandleInsertCharacter(char, doc);
      }
    }

    _resetComposition();
    _resetPlatformBuffer();
    doc.updateContent();
  }

  /// Cancels the active composition without mutating the document.
  void _cancelPreedit() {
    final doc = _document;
    _resetComposition();
    if (doc != null) {
      doc.cursor.imeComposing = false;
      _resetPlatformBuffer();
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
    _connection!.setEditingState(const TextEditingValue());
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

  /// Invalidates paint on the paragraph render that hosts the preedit.
  void _invalidatePreeditRender() {
    if (_document == null || _preeditContainerId.isEmpty) return;
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

  /// Returns true if the given container id is the one hosting the active preedit.
  bool isPreeditInContainer(String containerId) {
    return _isComposing && _preeditContainerId == containerId;
  }
}