import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fluent_editor/factories.dart'
    show Fragment, Paragraph, FluentImage;
import '../fluent_document.dart';
import '../handlers/handle_arrow_key.dart';
import '../handlers/handle_backspace.dart';
import '../handlers/handle_enter.dart';
import '../utils/node_operations.dart' show removeNode;
import 'ime_connection_manager.dart';
import 'ime_state_manager.dart';

const String _emptyFragmentPlaceholder = '\u200B';

/// Singleton handler for Flutter's [TextInputClient] and [DeltaTextInputClient] channels.
///
/// Manages IME composition (preedit underlines, CJK, accents, Gboard),
/// multi-fragment paragraph isolation for suggestion mode, platform buffer reconciliation,
/// and document text synchronization across macOS, iOS, Android, Web, and Windows.
class FluentTextInputHandler implements DeltaTextInputClient {
  static final FluentTextInputHandler _instance =
      FluentTextInputHandler._internal();

  factory FluentTextInputHandler() => _instance;

  final ImeStateManager state = ImeStateManager();
  late final ImeConnectionManager connectionManager;

  FluentTextInputHandler._internal() {
    connectionManager = ImeConnectionManager(this);
  }

  FluentDocument? _document;

  FluentDocument? get document => _document;
  bool get isComposing => state.isComposing;
  String get preeditText => state.preeditText;
  String get preeditFragmentId => state.preeditFragmentId;
  int get preeditLocalOffset => state.preeditLocalOffset;

  bool isPreeditInContainer(String containerId) =>
      state.isPreeditInContainer(containerId);

  void showKeyboard(BuildContext context) {
    connectionManager.showKeyboard(
      context,
      onSyncBuffer: syncImeBufferToFragment,
    );
  }

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  bool get _shouldSyncBuffer =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  // ===========================================================================
  // Input Lifecycle
  // ===========================================================================

  void attachInput(FluentDocument doc) {
    _document = doc;
    state.attachInput();
    connectionManager.attachInput(doc);
    syncImeBufferToFragment();
  }

  void detachInput() {
    connectionManager.detachInput();
    state.detachInput();
    _document = null;
  }

  // ===========================================================================
  // TextInputClient / DeltaTextInputClient Callbacks
  // ===========================================================================

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  TextEditingValue? get currentTextEditingValue {
    final text = _getCurrentFragmentText() ?? '';
    final offset = _getCursorOffsetInFragment();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    connectionManager.connection = null;
  }

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void showToolbar() {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void performAction(TextInputAction action) {
    final doc = _document;
    if (doc == null) return;
    if (action == TextInputAction.newline ||
        action == TextInputAction.done ||
        action == TextInputAction.go ||
        action == TextInputAction.send) {
      commitIfComposing();
      executeHandleEnter(doc);
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void performSelector(String selectorName) {
    final doc = _document;
    if (doc == null) return;
    switch (selectorName) {
      case 'moveLeft:':
        executeHandleArrowKey(LogicalKeyboardKey.arrowLeft, doc);
        break;
      case 'moveRight:':
        executeHandleArrowKey(LogicalKeyboardKey.arrowRight, doc);
        break;
      case 'deleteBackward:':
        executeHandleBackspace(doc);
        break;
    }
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    final doc = _document;
    if (doc == null) return;
    if (state.updatingSelf) return;

    final cursor = doc.cursor;
    final fragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    final currentText = _getCurrentFragmentText() ?? '';

    // ignore: avoid_print
    print(
      '[IME_DEBUG] updateEditingValue text="${value.text}" '
      'selection=${value.selection} composing=${value.composing}',
    );

    // -------------------------------------------------------------------------
    // 1. Preedit Active / Updating
    // -------------------------------------------------------------------------
    if (value.composing.isValid) {
      final wasComposing = state.isComposing;
      if (!doc.cursor.isCollapsed && !wasComposing) {
        executeHandleBackspace(doc);
      }
      final hasPlaceholder = value.text.startsWith(_emptyFragmentPlaceholder);
      final rawStart = (hasPlaceholder && value.composing.start > 0)
          ? (value.composing.start - 1).clamp(0, value.text.length)
          : value.composing.start.clamp(0, value.text.length);
      final rawEnd = (hasPlaceholder && value.composing.end > 0)
          ? (value.composing.end - 1).clamp(0, value.text.length)
          : value.composing.end.clamp(0, value.text.length);
      final actualStart = value.composing.start.clamp(0, value.text.length);
      final actualEnd = value.composing.end.clamp(0, value.text.length);
      final rawPreedit = value.text.substring(actualStart, actualEnd);

      state.preeditFragmentId = fragId;
      if (!wasComposing) {
        state.isComposing = true;
        final initialOffset = cursor.isCollapsed
            ? cursor.focusOffset
            : (cursor.anchorOffset < cursor.focusOffset
                  ? cursor.anchorOffset
                  : cursor.focusOffset);
        state.preeditLocalOffset = initialOffset;
        state.lastSyncedText = _getCurrentFragmentText() ?? '';
        final parentId = doc.findParentCached(fragId);
        state.preeditContainerId = parentId ?? '';
        state.justCommittedComposition = false;
      }
      state.isComposing = true;

      if (rawPreedit.isNotEmpty) {
        final preeditText = _extractPreeditText(value);
        if (preeditText.isNotEmpty) {
          state.preeditText = preeditText;
          state.composingRange = TextRange(start: 0, end: preeditText.length);
          state.preeditCaretOffset = value.selection.isValid
              ? (value.selection.extentOffset - rawStart).clamp(
                  0,
                  preeditText.length,
                )
              : preeditText.length;

          cursor.imeComposing = true;
          cursor.imeComposingStart = state.preeditLocalOffset;

          final targetNode = doc.nodeById(fragId);
          if (targetNode is Fragment && targetNode.text.isNotEmpty) {
            if (rawStart >= 0 && rawEnd <= value.text.length) {
              final prefixText = value.text.substring(0, rawStart);
              final suffixText = value.text.substring(rawEnd);
              if (targetNode.text == prefixText + preeditText + suffixText) {
                targetNode.text = prefixText + suffixText;
                doc.cursor.moveTo(fragId, rawStart);
              }
            }
          }
        }
      }

      doc.selectionManager.clear();
      _invalidatePreeditRender();
      return;
    }

    // -------------------------------------------------------------------------
    // 2. Post-Commit Platform Buffer Sync Guard
    // -------------------------------------------------------------------------
    if (state.justCommittedComposition) {
      if (!value.composing.isValid) {
        state.justCommittedComposition = false;
        if (state.lastCommittedText.isEmpty ||
            value.text.contains(state.lastCommittedText)) {
          final parentId = doc.findParentCached(fragId);
          final paragraphNode = parentId != null
              ? doc.nodeById(parentId)
              : null;
          if (paragraphNode is Paragraph) {
            final pText = paragraphNode.text;
            if (pText == value.text ||
                (value.text.isNotEmpty && pText.contains(value.text)) ||
                (pText.isNotEmpty && value.text.contains(pText))) {
              state.lastSyncedText = value.text;
              return;
            }
          }
          state.lastSyncedText = value.text;
          syncImeBufferToFragment();
          return;
        }
      }
    }

    // -------------------------------------------------------------------------
    // 3. Composition Transition / Commit
    // -------------------------------------------------------------------------
    if (state.isComposing) {
      if (value.text.isNotEmpty) {
        final (prefix, suffix) = _getParagraphPrefixAndSuffix();
        final prefixPos = prefix.isNotEmpty ? value.text.indexOf(prefix) : 0;
        final suffixPos = suffix.isNotEmpty
            ? _findSuffixPos(value.text, suffix)
            : value.text.length;
        if (prefixPos != -1 &&
            suffixPos != -1 &&
            suffixPos >= prefixPos + prefix.length) {
          final extracted = value.text.substring(
            prefixPos + prefix.length,
            suffixPos,
          );
          final current = _getCurrentFragmentText() ?? '';
          if (extracted.isNotEmpty &&
              extracted != current &&
              !current.contains(extracted)) {
            final cleaned =
                (state.preeditText.isNotEmpty &&
                    extracted.trim() == state.preeditText.trim())
                ? state.preeditText
                : extracted.trim();
            if (cleaned.isNotEmpty) {
              state.preeditText = _sanitizeUtf16(cleaned);
            }
          }
        }
      }
      final textToCommit = state.preeditText;
      if (textToCommit.isNotEmpty) {
        _commitPreedit(textToCommit);
      }
      _resetComposition();
      _invalidatePreeditRender();
      if (!value.composing.isValid) {
        state.lastSyncedText = value.text;
        syncImeBufferToFragment();
        return;
      }
    }

    // -------------------------------------------------------------------------
    // 4. Non-Composing Text Edits (Typing, Selection Replace, Deletion)
    // -------------------------------------------------------------------------
    final oldText = currentText;
    final newText = value.text;

    if (!cursor.isCollapsed) {
      if (newText != oldText) {
        final inserted = _computeInsertedText(oldText, newText);
        doc.saveState(description: 'Replace selection', forceNewAction: false);
        if (inserted.isNotEmpty) {
          _insertFinalizedText(inserted);
        } else {
          _replaceFragmentText(
            newText,
            cursorOffset: value.selection.extentOffset,
          );
        }
        _resetPlatformBuffer();
        return;
      }
    }

    if (newText.length > oldText.length) {
      var prefixLen = _commonPrefixLength(oldText, newText);
      if (prefixLen == oldText.length &&
          oldText.isNotEmpty &&
          !oldText.endsWith(' ')) {
        final lastSpace = oldText.lastIndexOf(' ');
        final lastWordStart = lastSpace == -1 ? 0 : lastSpace + 1;
        final lastWord = oldText.substring(lastWordStart);
        if (lastWord.isNotEmpty &&
            lastWordStart < newText.length &&
            newText.substring(lastWordStart).startsWith(lastWord)) {
          final newTail = newText.substring(lastWordStart);
          if (newTail.length > lastWord.length &&
              (newTail.endsWith(' ') || newTail.contains(' '))) {
            prefixLen = lastWordStart;
          }
        }
      }
      final suffixLen = _commonSuffixLength(
        oldText.substring(prefixLen),
        newText.substring(prefixLen),
      );
      final oldReplaced = oldText.substring(
        prefixLen,
        oldText.length - suffixLen,
      );
      final newInserted = newText.substring(
        prefixLen,
        newText.length - suffixLen,
      );

      if (oldReplaced.isNotEmpty) {
        doc.saveState(description: 'Candidate replace', forceNewAction: false);
        final containerId = doc.findLogicalContainerId(fragId) ?? fragId;
        doc.cursor.anchorId = fragId;
        doc.cursor.anchorOffset = prefixLen;
        doc.cursor.focusId = fragId;
        doc.cursor.focusOffset = prefixLen + oldReplaced.length;
        doc.selectionManager.startSelection(containerId, fragId, prefixLen);
        doc.selectionManager.updateFocus(
          containerId,
          fragId,
          prefixLen + oldReplaced.length,
        );
        _insertFinalizedText(newInserted);
        _resetPlatformBuffer();
        return;
      } else {
        final inserted = _computeInsertedText(oldText, newText);
        if (inserted.isNotEmpty) {
          doc.saveState(description: 'Type', forceNewAction: false);
          doc.cursor.moveTo(fragId, prefixLen);
          _insertFinalizedText(inserted);
        }
      }
    } else if (newText.length < oldText.length) {
      doc.saveState(description: 'Delete', forceNewAction: false);
      if (oldText.length > newText.length) {
        executeHandleBackspace(doc);
      } else {
        _replaceFragmentText(
          newText,
          cursorOffset: value.selection.extentOffset,
        );
      }
    }

    syncImeBufferToFragment();
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> deltas) {
    final doc = _document;
    if (doc == null) return;
    if (state.updatingSelf) return;

    if (state.isComposing) {
      final last = deltas.last;
      updateEditingValue(
        TextEditingValue(
          text: last.oldText,
          selection: last.selection,
          composing: last.composing,
        ),
      );
      return;
    }

    if (state.justCommittedComposition) {
      state.justCommittedComposition = false;
      return;
    }

    for (final delta in deltas) {
      // ignore: avoid_print
      print(
        '[IME_DEBUG] delta: ${delta.runtimeType} oldText="${delta.oldText}" '
        'selection=${delta.selection} composing=${delta.composing}',
      );

      if (delta is TextEditingDeltaDeletion ||
          (delta is TextEditingDeltaReplacement &&
              delta.replacementText.isEmpty)) {
        doc.saveState(description: 'Delete', forceNewAction: false);
        if (!doc.cursor.isCollapsed) {
          executeHandleBackspace(doc);
          _resetPlatformBuffer();
          return;
        }
        final deletionRange = delta is TextEditingDeltaDeletion
            ? delta.deletedRange
            : (delta as TextEditingDeltaReplacement).replacedRange;
        if (deletionRange.isValid && deletionRange.start < deletionRange.end) {
          final oldText = delta.oldText;
          final deleteStart = deletionRange.start.clamp(0, oldText.length);
          final deleteEnd = deletionRange.end.clamp(0, oldText.length);
          final deletedText = oldText.substring(deleteStart, deleteEnd);
          final count = deletedText.characters.length;
          for (var i = 0; i < count; i++) {
            executeHandleBackspace(doc);
          }
        } else {
          executeHandleBackspace(doc);
        }
        _resetPlatformBuffer();
        return;
      }

      if (delta is TextEditingDeltaInsertion) {
        doc.saveState(description: 'Type', forceNewAction: false);
        if (delta.textInserted.contains('\n')) {
          _insertFinalizedText(delta.textInserted);
          _resetPlatformBuffer();
          return;
        }
        if (delta.composing.isValid &&
            delta.composing.start < delta.composing.end) {
          state.isComposing = true;
          state.preeditText = delta.textInserted;
          state.composingRange = delta.composing;
          state.preeditLocalOffset = doc.cursor.focusOffset;
          final fragId = doc.cursor.focusId.isNotEmpty
              ? doc.cursor.focusId
              : doc.cursor.anchorId;
          final parentId = doc.findParentCached(fragId);
          state.preeditContainerId = parentId ?? '';
          doc.cursor.imeComposing = true;
          doc.cursor.imeComposingStart = state.preeditLocalOffset;
          _invalidatePreeditRender();
          return;
        }
        _insertFinalizedText(delta.textInserted);
        _resetPlatformBuffer();
        return;
      }

      if (delta is TextEditingDeltaReplacement) {
        doc.saveState(description: 'Replace', forceNewAction: false);
        final replacementText = delta.replacementText;
        final oldText = delta.oldText;

        if (delta.replacedRange.isValid &&
            delta.replacedRange.start <= delta.replacedRange.end &&
            delta.replacedRange.end <= oldText.length) {
          final start = delta.replacedRange.start;
          final end = delta.replacedRange.end;
          final oldSlice = oldText.substring(start, end);
          final inserted = _computeInsertedText(oldSlice, replacementText);

          final fragId = doc.cursor.focusId.isNotEmpty
              ? doc.cursor.focusId
              : doc.cursor.anchorId;
          final node = doc.nodeById(fragId);

          if (inserted.isNotEmpty) {
            final targetOffset =
                start +
                (replacementText.length - inserted.length).clamp(
                  0,
                  replacementText.length,
                );
            if (node is Fragment) {
              final localOffset = targetOffset.clamp(0, node.text.length);
              doc.cursor.moveTo(fragId, localOffset);
            }
            _insertFinalizedText(inserted);
            _resetPlatformBuffer();
            return;
          }
        }

        final inserted = _computeInsertedText(oldText, replacementText);
        if (inserted.isNotEmpty) {
          _insertFinalizedText(inserted);
        } else {
          _replaceFragmentText(replacementText);
        }
        _resetPlatformBuffer();
        return;
      }
    }
  }

  // ===========================================================================
  // Composition Engine & Preedit Extraction
  // ===========================================================================

  void commitIfComposing() {
    if (!state.isComposing) return;
    final text = state.preeditText;
    if (text.isNotEmpty) {
      _commitPreedit(text);
    } else {
      _resetComposition();
    }
    _invalidatePreeditRender();
  }

  void _commitPreedit(String text) {
    final doc = _document;
    if (doc == null || text.isEmpty) return;
    state.updatingSelf = true;
    doc.saveState(description: 'IME Commit', forceNewAction: true);
    final targetFragId =
        (!doc.cursor.isCollapsed || state.preeditFragmentId.isEmpty)
        ? (doc.cursor.focusId.isNotEmpty
              ? doc.cursor.focusId
              : doc.cursor.anchorId)
        : state.preeditFragmentId;
    final targetOffset = doc.cursor.isCollapsed
        ? state.preeditLocalOffset
        : doc.cursor.focusOffset;
    if (doc.cursor.isCollapsed) {
      doc.cursor.moveTo(targetFragId, targetOffset);
    }

    // ignore: avoid_print
    print(
      '[IME_DEBUG] _commitPreedit text="$text" targetFragId="$targetFragId" '
      'targetOffset=$targetOffset preeditText="${state.preeditText}"',
    );

    if (!doc.registry.dispatchImeCompositionCommit(text, doc)) {
      _insertTextOrReplaceSelection(text, doc);
    }
    _resetComposition();
    state.justCommittedComposition = true;
    state.lastCommittedText = text;
    state.updatingSelf = false;
    if (_shouldSyncBuffer) {
      syncImeBufferToFragment();
    }
  }

  void _resetComposition() {
    state.resetComposition();
    final doc = _document;
    if (doc != null) {
      doc.cursor.imeComposing = false;
      doc.cursor.imeComposingStart = 0;
    }
  }

  void _invalidatePreeditRender() {
    _document?.updateContent();
  }

  (String, String) _getParagraphPrefixAndSuffix() {
    final doc = _document;
    if (doc == null) return ('', '');
    final targetFragId = state.preeditFragmentId.isNotEmpty
        ? state.preeditFragmentId
        : (doc.cursor.focusId.isNotEmpty
              ? doc.cursor.focusId
              : doc.cursor.anchorId);
    if (targetFragId.isEmpty) return ('', '');

    doc.invalidateNodeIndex();
    final parentId = doc.findParentCached(targetFragId);
    if (parentId == null) {
      final node = doc.nodeById(targetFragId);
      if (node is Fragment) {
        final text = node.text.isNotEmpty ? node.text : state.lastSyncedText;
        final offset = state.preeditLocalOffset.clamp(0, text.length);
        final endOffset = (offset + state.preeditText.length).clamp(
          offset,
          text.length,
        );
        return (text.substring(0, offset), text.substring(endOffset));
      }
      return ('', '');
    }

    final paragraphNode = doc.nodeById(parentId);
    if (paragraphNode is! Paragraph) {
      final node = doc.nodeById(targetFragId);
      if (node is Fragment) {
        final text = node.text.isNotEmpty ? node.text : state.lastSyncedText;
        final offset = state.preeditLocalOffset.clamp(0, text.length);
        final endOffset = (offset + state.preeditText.length).clamp(
          offset,
          text.length,
        );
        return (text.substring(0, offset), text.substring(endOffset));
      }
      return ('', '');
    }

    doc.invalidateNodeIndex();
    doc.flattenContainer(paragraphNode);
    final paragraphText = paragraphNode.text;
    final targetFrag = doc.nodeById(targetFragId);
    final targetFragTextLen = targetFrag is Fragment
        ? targetFrag.text.length
        : 0;

    final fragStart = doc.getGlobalOffsetInParagraph(
      paragraphNode.id,
      targetFragId,
      0,
    );
    final fragEnd = doc.getGlobalOffsetInParagraph(
      paragraphNode.id,
      targetFragId,
      targetFragTextLen,
    );

    if (fragStart == null || fragEnd == null) {
      return ('', '');
    }

    final fragText = state.isComposing && state.lastSyncedText.isNotEmpty
        ? state.lastSyncedText
        : (targetFrag is Fragment ? targetFrag.text : '');
    final localOffset = state.preeditLocalOffset;
    final offset = localOffset.clamp(0, fragText.length);
    final hasPreedit =
        state.preeditText.isNotEmpty && fragText.contains(state.preeditText);
    final endIdx = hasPreedit ? offset + state.preeditText.length : offset;
    final localEnd = endIdx.clamp(offset, fragText.length);

    final fragPrefix = state.isComposing ? fragText.substring(0, offset) : '';
    final fragSuffix = state.isComposing ? fragText.substring(localEnd) : '';

    final isSingleFrag =
        paragraphNode.fragments.whereType<Fragment>().length <= 1;
    final paraPrefix = isSingleFrag
        ? ''
        : paragraphText.substring(0, fragStart.clamp(0, paragraphText.length));
    final paraSuffix = isSingleFrag
        ? ''
        : paragraphText.substring(fragEnd.clamp(0, paragraphText.length));

    final prefix = paraPrefix + fragPrefix;
    final suffix = fragSuffix + paraSuffix;
    return (prefix, suffix);
  }

  int _findSuffixPos(String text, String suffix) {
    if (suffix.isEmpty) return text.length;
    var pos = text.lastIndexOf(suffix);
    if (pos != -1) return pos;
    for (var len = suffix.length - 1; len > 0; len--) {
      final sub = suffix.substring(suffix.length - len);
      pos = text.lastIndexOf(sub);
      if (pos != -1) return pos;
    }
    return -1;
  }

  String _extractPreeditText(TextEditingValue value) {
    if (value.composing.isValid) {
      final rawStart = value.composing.start.clamp(0, value.text.length);
      final rawEnd = value.composing.end.clamp(0, value.text.length);
      if (rawStart < rawEnd) {
        final rawPreedit = value.text.substring(rawStart, rawEnd);
        final clean = _sanitizeUtf16(
          rawPreedit,
        ).replaceAll(_emptyFragmentPlaceholder, '');
        if (clean.isNotEmpty) {
          return clean;
        }
      }
    }

    if (value.text.isNotEmpty) {
      final (prefix, suffix) = _getParagraphPrefixAndSuffix();
      final prefixPos = prefix.isNotEmpty ? value.text.indexOf(prefix) : 0;
      final suffixPos = suffix.isNotEmpty
          ? _findSuffixPos(value.text, suffix)
          : value.text.length;
      if (prefixPos != -1 &&
          suffixPos != -1 &&
          suffixPos >= prefixPos + prefix.length) {
        final extracted = value.text.substring(
          prefixPos + prefix.length,
          suffixPos,
        );
        final clean = _sanitizeUtf16(
          extracted,
        ).replaceAll(_emptyFragmentPlaceholder, '');
        if (clean.isNotEmpty) {
          return clean;
        }
      }
    }

    return '';
  }

  // ===========================================================================
  // Buffer Synchronization & Text Insertion Helpers
  // ===========================================================================

  void syncImeBufferToFragment() {
    if (connectionManager.connection == null ||
        !connectionManager.connection!.attached)
      return;
    if (state.isComposing) return;
    final doc = _document;
    if (doc == null) return;
    final currentFragId = doc.cursor.focusId.isNotEmpty
        ? doc.cursor.focusId
        : doc.cursor.anchorId;

    if (currentFragId != state.lastSyncedFragmentId) {
      _resetPlatformBuffer();
    }
    state.lastSyncedFragmentId = currentFragId;

    if (!_shouldSyncBuffer) {
      return;
    }

    final text = _getCurrentFragmentText();
    if (text == null) {
      _resetPlatformBuffer();
      return;
    }
    final cursor = doc.cursor;
    final isSingleFragSelection =
        !cursor.isCollapsed && cursor.anchorId == cursor.focusId;
    final isMultiFragSelection =
        !cursor.isCollapsed && cursor.anchorId != cursor.focusId;
    final offset = _getCursorOffsetInFragment();
    final bool usePlaceholder =
        _isIOS &&
        cursor.isCollapsed &&
        offset == 0 &&
        !text.startsWith(_emptyFragmentPlaceholder);
    final syncedText = usePlaceholder
        ? '$_emptyFragmentPlaceholder$text'
        : text;
    final syncedOffset = usePlaceholder
        ? 1
        : offset.clamp(0, syncedText.length);
    final TextSelection syncedSelection;
    if (isSingleFragSelection && !usePlaceholder) {
      syncedSelection = TextSelection(
        baseOffset: cursor.anchorOffset.clamp(0, syncedText.length),
        extentOffset: cursor.focusOffset.clamp(0, syncedText.length),
      );
    } else if (isMultiFragSelection && !usePlaceholder) {
      syncedSelection = TextSelection(
        baseOffset: 0,
        extentOffset: syncedText.length,
      );
    } else {
      syncedSelection = TextSelection.collapsed(offset: syncedOffset);
    }

    final selectionChanged =
        state.prevSelectionKey !=
        '${syncedSelection.baseOffset}:${syncedSelection.extentOffset}';
    state.prevSelectionKey =
        '${syncedSelection.baseOffset}:${syncedSelection.extentOffset}';

    final wasUpdatingSelf = state.updatingSelf;
    state.updatingSelf = true;
    try {
      if (kIsWeb && syncedText.length < state.lastSyncedText.length) {
        connectionManager.connection!.setEditingState(const TextEditingValue());
      }
      if (_isIOS && selectionChanged) {
        connectionManager.connection!.setEditingState(const TextEditingValue());
      }
      connectionManager.connection!.setEditingState(
        TextEditingValue(
          text: syncedText,
          selection: syncedSelection,
          composing: TextRange.empty,
        ),
      );
      state.lastSyncedText = syncedText;
    } finally {
      state.updatingSelf = wasUpdatingSelf;
    }
  }

  void _insertFinalizedText(String text) {
    final doc = _document;
    if (doc == null) return;
    if (text == '\n') {
      executeHandleEnter(doc);
      return;
    }
    if (!doc.registry.dispatchInsertText(text, doc)) {
      _insertTextOrReplaceSelection(text, doc);
    }
  }

  void _insertTextOrReplaceSelection(String text, FluentDocument doc) {
    if (doc.cursor.isCollapsed) {
      final fragId = doc.cursor.focusId.isNotEmpty
          ? doc.cursor.focusId
          : doc.cursor.anchorId;
      final node = doc.nodeById(fragId);
      if (node is Fragment) {
        final localOffset = doc.cursor.focusOffset.clamp(0, node.text.length);
        final before = node.text.substring(0, localOffset);
        final after = node.text.substring(localOffset);
        node.text = before + text + after;
        doc.cursor.moveTo(fragId, localOffset + text.length);
      }
    } else {
      executeHandleBackspace(doc);
      final fragId = doc.cursor.focusId.isNotEmpty
          ? doc.cursor.focusId
          : doc.cursor.anchorId;
      final node = doc.nodeById(fragId);
      if (node is Fragment) {
        final localOffset = doc.cursor.focusOffset.clamp(0, node.text.length);
        final before = node.text.substring(0, localOffset);
        final after = node.text.substring(localOffset);
        node.text = before + text + after;
        doc.cursor.moveTo(fragId, localOffset + text.length);
      }
    }
    doc.updateContent();
  }

  void _replaceFragmentText(String newText, {int? cursorOffset}) {
    final doc = _document;
    if (doc == null) return;
    final fragId = doc.cursor.focusId.isNotEmpty
        ? doc.cursor.focusId
        : doc.cursor.anchorId;
    final node = doc.nodeById(fragId);
    if (node is! Fragment) return;
    if (node is FluentImage) {
      removeNode(doc.content, node);
      doc.updateContent();
      return;
    }
    doc.saveState(description: 'Replace text', forceNewAction: false);
    final cleanText = _sanitizeUtf16(newText);
    node.text = cleanText;
    final finalOffset = _snapCursorOffset(
      cleanText,
      cursorOffset ?? cleanText.length,
    );
    doc.cursor.moveTo(fragId, finalOffset);
    doc.selectionManager.collapse();
    doc.updateContent();
    syncImeBufferToFragment();
  }

  void _resetPlatformBuffer() {
    state.lastSyncedText = '';
    state.prevSelectionKey = '';
    if (connectionManager.connection != null &&
        connectionManager.connection!.attached) {
      connectionManager.connection!.setEditingState(const TextEditingValue());
    }
  }

  String _computeInsertedText(String oldText, String newText) {
    if (newText.startsWith(oldText)) {
      return newText.substring(oldText.length);
    }
    if (newText.endsWith(oldText)) {
      return newText.substring(0, newText.length - oldText.length);
    }
    var prefixLen = 0;
    while (prefixLen < oldText.length &&
        prefixLen < newText.length &&
        oldText[prefixLen] == newText[prefixLen]) {
      prefixLen++;
    }
    var suffixLen = 0;
    while (suffixLen < (oldText.length - prefixLen) &&
        suffixLen < (newText.length - prefixLen) &&
        oldText[oldText.length - 1 - suffixLen] ==
            newText[newText.length - 1 - suffixLen]) {
      suffixLen++;
    }
    return newText.substring(prefixLen, newText.length - suffixLen);
  }

  String? _getCurrentFragmentText() {
    final doc = _document;
    if (doc == null) return null;
    final fragId = doc.cursor.focusId.isNotEmpty
        ? doc.cursor.focusId
        : doc.cursor.anchorId;
    final node = doc.nodeById(fragId);
    if (node is Fragment && node is! FluentImage) {
      return node.text;
    }
    return null;
  }

  int _getCursorOffsetInFragment() {
    final doc = _document;
    if (doc == null) return 0;
    final cursor = doc.cursor;
    final fragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    final node = doc.nodeById(fragId);
    if (node is Fragment) {
      return cursor.focusOffset.clamp(0, node.text.length);
    }
    return 0;
  }

  int _snapCursorOffset(String text, int rawOffset) {
    if (rawOffset <= 0) return 0;
    if (rawOffset >= text.length) return text.length;
    final units = text.codeUnits;
    if (rawOffset > 0 && rawOffset < units.length) {
      final prev = units[rawOffset - 1];
      final curr = units[rawOffset];
      if (prev >= 0xD800 &&
          prev <= 0xDBFF &&
          curr >= 0xDC00 &&
          curr <= 0xDFFF) {
        return rawOffset + 1 <= text.length ? rawOffset + 1 : text.length;
      }
    }
    return rawOffset;
  }

  String _sanitizeUtf16(String text) {
    if (text.isEmpty) return text;
    final units = text.codeUnits;
    final result = <int>[];
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 < units.length &&
            units[i + 1] >= 0xDC00 &&
            units[i + 1] <= 0xDFFF) {
          result.add(unit);
          result.add(units[i + 1]);
          i++;
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        // Drop orphan low surrogate
      } else {
        result.add(unit);
      }
    }
    return String.fromCharCodes(result);
  }

  bool get isConnectionActive => connectionManager.isConnectionActive;

  bool get shouldUseBufferSync =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  void setViewHeight(double height) => connectionManager.setViewHeight(height);

  void updateCaretRect(Rect rect) => connectionManager.updateCaretRect(rect);

  int _commonPrefixLength(String a, String b) {
    int i = 0;
    while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  int _commonSuffixLength(String a, String b) {
    int i = a.length - 1;
    int j = b.length - 1;
    int len = 0;
    while (i >= 0 && j >= 0 && a.codeUnitAt(i) == b.codeUnitAt(j)) {
      len++;
      i--;
      j--;
    }
    return len;
  }
}
