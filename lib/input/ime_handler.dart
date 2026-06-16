import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_insert_character.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/handlers/handle_enter.dart';

/// Singleton IME handler that implements [TextInputClient] for Flutter's
/// system text input channel. Preedit text is kept isolated from the document
/// model and only committed when the composition genuinely ends.
class FluentTextInputHandler with DeltaTextInputClient {
  static final FluentTextInputHandler _instance = FluentTextInputHandler._internal();
  factory FluentTextInputHandler() => _instance;
  FluentTextInputHandler._internal();

  TextInputConnection? _connection;
  FluentDocument? _document;

  /// Current preedit text displayed to the user but not yet committed.
  String _preeditText = '';
  String get preeditText => _preeditText;

  /// Offset in the document (fragment id + local offset) where preedit starts.
  String _preeditFragmentId = '';
  int _preeditLocalOffset = 0;
  String _preeditContainerId = '';

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
    return TextEditingValue(
      text: _preeditText,
      selection: TextSelection.collapsed(offset: _preeditText.length),
      composing: _composingRange,
    );
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (_updatingSelf) return;
    if (_document == null) return;

    // Reconstruct the final TextEditingValue by applying deltas sequentially.
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

    // ─── Active composition handling ────────────────────────────────
    if (_isComposing) {
      if (value.composing.isValid) {
        // Still composing: just update the preedit underline. This is the
        // common case while Gboard/iOS keep revising the candidate text.
        _preeditText = value.text;
        _composingRange = value.composing;
        _invalidatePreeditRender();
        return;
      }

      // composing became invalid. This does NOT always mean "the user
      // confirmed the word" — many IMEs (Gboard in particular, with
      // autocorrect/suggestions enabled) emit one or more intermediate
      // updates where `composing` is temporarily empty/invalid even though
      // the user is still mid-word and suggestions are still showing.
      //
      // composing became invalid while we were composing -> this is a
      // genuine commit (or cancel if the text was deleted to empty).
      if (value.text.isEmpty) {
        _cancelPreedit();
        return;
      }

      _commitPreedit(value.text);
      return;
    }

    // ─── New composition start ────────────────────────────────────
    // Only treat this as the start of a *composition* (i.e. preedit that
    // must be isolated from the document) when the platform actually marks
    // a composing range. If the IME sends already-finalized text with no
    // composing range (e.g. a single committed keystroke, or a suggestion
    // tapped without ever showing an underline), insert it directly instead
    // of parking it in the preedit buffer — otherwise it sits there
    // displayed-but-uncommitted until some later, unrelated event flushes
    // it, which is exactly the "text appears before it's confirmed" bug.
    if (value.text.isEmpty) return;

    if (!value.composing.isValid) {
      _insertFinalizedText(value.text);
      return;
    }

    // If the user had an active selection when composition started (e.g.
    // selected a word and started typing over it via the IME), that
    // selection must be deleted NOW, while we still know about it. Once we
    // call selectionManager.clear() below, the selection highlight is gone
    // from SelectionManager's state but the *document* still contains the
    // old selected text — clear() only clears the highlight, it does not
    // delete content. If we don't delete it here, the committed IME text
    // will be inserted next to the old text instead of replacing it.
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
    _invalidatePreeditRender();
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
  }

  /// Invalidates paint on the paragraph render that hosts the preedit.
  void _invalidatePreeditRender() {
    if (_document == null || _preeditContainerId.isEmpty) return;
    final render = _document!.paragraphRegistry.renderFor(_preeditContainerId);
    if (render != null) {
      render.imePreeditText = _preeditText;
      render.imeComposingRange = _composingRange;
      render.imePreeditFragmentId = _preeditFragmentId;
      render.imePreeditLocalOffset = _preeditLocalOffset;
      render.markNeedsPaint();
    }
  }

  /// Returns true if the given container id is the one hosting the active preedit.
  bool isPreeditInContainer(String containerId) {
    return _isComposing && _preeditContainerId == containerId;
  }
}