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
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.macOS ||
                  defaultTargetPlatform == TargetPlatform.windows);

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
    _lastSyncedFragmentId = '';
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
  }

  /// Opens the keyboard (requests focus from the platform text input).
  void showKeyboard(BuildContext context) {
    // Extract viewId from the current window using the context
    final int viewId = View.of(context).viewId;

    if (_connection == null || !_connection!.attached) {
      _attachConnection(viewId: viewId);
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
        debugPrint(
          'FluentTextInputHandler: Windows view ID null, retry $_connectionRetryCount/${_maxConnectionRetries} '
          'after ${delay.inMilliseconds}ms',
        );
        _connectionRetryTimer?.cancel();
        _connectionRetryTimer = Timer(delay, () {
          _connectionRetryTimer = null;
          _attachConnection(viewId: viewId); // Retry with the same viewId
        });
        return false; // Return false to indicate not ready yet, WITHOUT crashing
      }
      // If error is different or we exhausted retries, log it
      debugPrint(
        'FluentTextInputHandler: Failed to attach text input definitively: '
        '${e.code} - ${e.message}',
      );
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
    // iOS/macOS/Windows: sync buffer with current fragment text for proper IME behavior
    // (autocorrect, predictive text, suggestions).
    if (_shouldSyncBuffer) {
      final text = _getCurrentFragmentText();
      if (text != null) {
        final offset = _getCursorOffsetInFragment();
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

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    if (_updatingSelf) return;
    if (_structuralChangeInProgress) return;
    if (_document == null) return;

    // Check if we're handling preedit/composing data - sanitize at source
    if (deltas.any((d) => d.composing.isValid)) {
      // Apply deltas to get the final value, then sanitize it
      TextEditingValue value = currentTextEditingValue ?? const TextEditingValue();
      for (final delta in deltas) {
        value = delta.apply(value);
      }
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

            // Reset the IME buffer to EMPTY so iOS/macOS lose every
            // reference to the old text and compute subsequent deltas
            // against a clean slate.
            _resetPlatformBuffer();
            _lastSyncedFragmentId = _document!.cursor.focusId.isNotEmpty
                ? _document!.cursor.focusId
                : _document!.cursor.anchorId;

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
          
          // Handle emoji deletion on Windows: if deleting at start of surrogate pair,
          // expand deletion to include the complete emoji (2 code units)
          if (!_isMacOS && (delta is TextEditingDeltaDeletion ||
              (delta is TextEditingDeltaReplacement &&
                  delta.replacementText.isEmpty))) {
            final deletionRange = delta is TextEditingDeltaDeletion 
                ? delta.deletedRange 
                : (delta as TextEditingDeltaReplacement).replacedRange;
            
            // Check if we're deleting at the start of a surrogate pair (emoji)
            final deletionLength = deletionRange.end - deletionRange.start;
            if (deletionRange.isValid && deletionLength == 1) {
              final textBefore = value.text;
              final deleteStart = deletionRange.start.clamp(0, textBefore.length);
              if (deleteStart < textBefore.length) {
                final graphemeLen = FragmentOperations.getGraphemeLengthAt(textBefore, deleteStart);
                if (graphemeLen == 2) {
                  // This is an emoji - need to delete 2 code units
                  // Create a modified delta with expanded range
                  if (delta is TextEditingDeltaDeletion) {
                    final expandedDelta = TextEditingDeltaDeletion(
                      oldText: delta.oldText,
                      deletedRange: TextRange(start: deleteStart, end: deleteStart + 2),
                      selection: delta.selection,
                      composing: delta.composing,
                    );
                    value = expandedDelta.apply(value);
                  } else if (delta is TextEditingDeltaReplacement) {
                    final expandedDelta = TextEditingDeltaReplacement(
                      oldText: delta.oldText,
                      replacementText: '',
                      replacedRange: TextRange(start: deleteStart, end: deleteStart + 2),
                      selection: delta.selection,
                      composing: delta.composing,
                    );
                    value = expandedDelta.apply(value);
                  }
                  continue;
                }
              }
            }
          }
          
          value = delta.apply(value);
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
        TextEditingValue value = currentTextEditingValue ?? const TextEditingValue();
        for (final delta in deltas) {
          value = delta.apply(value);
        }
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
          
          // Handle emoji deletion: expand single-unit deletion to 2 if it's an emoji
          int deleteCount = 1;
          final deletionRange = delta is TextEditingDeltaDeletion 
              ? delta.deletedRange 
              : (delta as TextEditingDeltaReplacement).replacedRange;
          
          if (deletionRange.isValid && (deletionRange.end - deletionRange.start) == 1) {
            final oldText = delta.oldText;
            final deletePos = deletionRange.start.clamp(0, oldText.length);
            if (deletePos < oldText.length) {
              final graphemeLen = FragmentOperations.getGraphemeLengthAt(oldText, deletePos);
              if (graphemeLen == 2) {
                deleteCount = 2; // Emoji needs 2 code units
              }
            }
          }
          
          // Execute multiple backspaces if needed for emoji
          for (int i = 0; i < deleteCount; i++) {
            executeHandleBackspace(doc);
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
          
          for (final char in insertedText.characters) {
            if (!doc.cursor.isCollapsed) {
              executeHandleReplaceSelection(char, doc);
            } else {
              executeHandleInsertCharacter(char, doc);
            }
          }
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
            for (final char in replacementText.characters) {
              if (!doc.cursor.isCollapsed) {
                executeHandleReplaceSelection(char, doc);
              } else {
                executeHandleInsertCharacter(char, doc);
              }
            }
          }
          _resetPlatformBuffer();
        }
      }
      doc.updateContent();
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
  void updateEditingValue(TextEditingValue value, {int? cursorOffset}) {
    if (_updatingSelf) return;
    if (_structuralChangeInProgress) return;
    if (_document == null) return;

    final doc = _document!;
    final cursor = doc.cursor;

    // ─── iOS Standard IME Buffer Sync (no dummy string) ──────────
    if (_shouldSyncBuffer && !_isComposing) {
      final currentText = _getCurrentFragmentText() ?? '';
      final cursorOffset = _getCursorOffsetInFragment();

      // Skip our own echo
      if (value.text == currentText &&
          value.selection.isCollapsed &&
          value.selection.extentOffset == cursorOffset) {
        return;
      }

      // New composition started (CJK, emoji, etc.)
      if (value.composing.isValid) {
        // Defensive extraction to avoid cutting through surrogate pairs (emoji)
        final start = FragmentOperations.adjustIndex(value.text, value.composing.start.clamp(0, value.text.length));
        final end = FragmentOperations.adjustIndex(value.text, value.composing.end.clamp(0, value.text.length));
        final rawPreedit = value.text.substring(start, end);
        final preeditText = _sanitizeUtf16(rawPreedit);
        
        final wholeCleanText = _sanitizeUtf16(value.text);
        final currentFragText = _getCurrentFragmentText() ?? '';

        if (wholeCleanText != currentFragText) {
          _updatingSelf = true;
          final node = doc.nodeById(cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId);
          if (node is Fragment) {
            // Replace fragment text but EXCLUDE the temporary preedit
            // to avoid corrupting the actual rendered text
            final textBefore = wholeCleanText.substring(0, start);
            final textAfter = wholeCleanText.substring(end);
            node.text = _sanitizeUtf16(textBefore + textAfter);
          }
          _updatingSelf = false;
        }
        
        if (!cursor.isCollapsed) {
          doc.saveState(description: 'Replace selection', forceNewAction: false);
          executeHandleReplaceSelection('', doc);
        }
        _isComposing = true;
        _preeditFragmentId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
        _preeditLocalOffset = start;
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
        final diffIndex = _findDiffIndex(newText, oldText);
        if (diffIndex >= 0) {
          _moveCursorToFragmentOffset(diffIndex + 1);
          doc.saveState(description: 'Backspace', forceNewAction: false);
          executeHandleBackspace(doc);
          syncImeBufferToFragment();
          return;
        }
      }

      // Text replacement (suggestion, paste, etc.)
      if (newText != oldText) {
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

          node.text = _sanitizeUtf16(value.text);
          // Cursor position from the IME's selection after commit.
          final newCursorOffset = value.selection.isValid && value.selection.isCollapsed
              ? value.selection.extentOffset
              : value.text.length;
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

        // Reset the IME buffer to EMPTY so iOS/macOS lose every
        // reference to the old text and compute subsequent deltas
        // against a clean slate.
        _resetPlatformBuffer();
        _lastSyncedFragmentId = _document!.cursor.focusId.isNotEmpty
            ? _document!.cursor.focusId
            : _document!.cursor.anchorId;

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

  /// Inserts text that the platform reported as already finalized (no
  /// composing range at all), bypassing the preedit buffer entirely.
  void _insertFinalizedText(String text) {
    if (_document == null || text.isEmpty) return;
    final doc = _document!;

    doc.saveState(description: 'Insert text', forceNewAction: false);

    // Iterate through UTF-16 code units, but merge surrogate pairs into single characters
    int i = 0;
    while (i < text.length) {
      int charCode = text.codeUnitAt(i);
      
      // Check if this is a high surrogate (start of emoji)
      if (charCode >= 0xD800 && charCode <= 0xDBFF && i + 1 < text.length) {
        int nextCharCode = text.codeUnitAt(i + 1);
        // Check if next is a low surrogate
        if (nextCharCode >= 0xDC00 && nextCharCode <= 0xDFFF) {
          // This is a complete surrogate pair (emoji), insert as one character
          final emoji = text.substring(i, i + 2);
          if (!doc.cursor.isCollapsed) {
            executeHandleReplaceSelection(emoji, doc);
          } else {
            executeHandleInsertCharacter(emoji, doc);
          }
          i += 2;
          continue;
        }
      }
      
      // Regular single code unit character
      final char = text[i];
      if (!doc.cursor.isCollapsed) {
        executeHandleReplaceSelection(char, doc);
      } else {
        executeHandleInsertCharacter(char, doc);
      }
      i++;
    }

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

    // Insert the committed text character by character using the existing
    // handlers so pending font/styles are respected.
    // Iterate through UTF-16 code units, merging surrogate pairs
    int i = 0;
    while (i < text.length) {
      int charCode = text.codeUnitAt(i);
      
      // Check if this is a high surrogate (start of emoji)
      if (charCode >= 0xD800 && charCode <= 0xDBFF && i + 1 < text.length) {
        int nextCharCode = text.codeUnitAt(i + 1);
        // Check if next is a low surrogate
        if (nextCharCode >= 0xDC00 && nextCharCode <= 0xDFFF) {
          // This is a complete surrogate pair (emoji), insert as one character
          final emoji = text.substring(i, i + 2);
          if (!doc.cursor.isCollapsed) {
            executeHandleReplaceSelection(emoji, doc);
          } else {
            executeHandleInsertCharacter(emoji, doc);
          }
          i += 2;
          continue;
        }
      }
      
      // Regular single code unit character
      final char = text[i];
      if (!doc.cursor.isCollapsed) {
        executeHandleReplaceSelection(char, doc);
      } else {
        executeHandleInsertCharacter(char, doc);
      }
      i++;
    }

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
    final offset = _getCursorOffsetInFragment();
    _updatingSelf = true;
    try {
      _connection!.setEditingState(TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
        composing: TextRange.empty,
      ));
    } on PlatformException catch (e) {
      debugPrint('FluentTextInputHandler: syncImeBufferToFragment failed: ${e.message}');
    }
    _updatingSelf = false;
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