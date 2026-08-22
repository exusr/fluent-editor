import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:fluent_editor/factories.dart' show Fragment, Paragraph;
import '../fluent_document.dart';
import 'ime_handler.dart';

/// Dedicated execution branch for Linux platform Input Method Editor (IME) handling.
///
/// Encapsulates Linux desktop preedit composition lifecycles (IBus, Fcitx),
/// delta batch reconciliation, platform buffer updates, and caret rect positioning.
class LinuxImeHandler {
  const LinuxImeHandler();

  /// Processes [TextEditingValue] updates on Linux platform.
  void updateEditingValue(
    TextEditingValue value,
    FluentTextInputHandler handler,
  ) {
    final doc = handler.document;
    if (doc == null || handler.state.updatingSelf) return;

    final cursor = doc.cursor;

    // -------------------------------------------------------------------------
    // 1. Preedit Active / Updating
    // -------------------------------------------------------------------------
    if (value.composing.isValid) {
      final wasComposing = handler.state.isComposing;
      if (!cursor.isCollapsed && !wasComposing) {
        handler.executeBackspace();
        doc.selectionManager.clear();
      }

      final fragId = cursor.focusId.isNotEmpty
          ? cursor.focusId
          : cursor.anchorId;

      final hasPlaceholder = value.text.startsWith('\u200B');
      final rawStart = (hasPlaceholder && value.composing.start > 0)
          ? (value.composing.start - 1).clamp(0, value.text.length)
          : value.composing.start.clamp(0, value.text.length);
      final rawEnd = (hasPlaceholder && value.composing.end > 0)
          ? (value.composing.end - 1).clamp(0, value.text.length)
          : value.composing.end.clamp(0, value.text.length);
      final actualStart = value.composing.start.clamp(0, value.text.length);
      final actualEnd = value.composing.end.clamp(0, value.text.length);
      final rawPreedit = value.text.substring(actualStart, actualEnd);

      handler.state.preeditFragmentId = fragId;
      if (!wasComposing) {
        handler.state.isComposing = true;
        final initialOffset = cursor.isCollapsed
            ? cursor.focusOffset
            : (cursor.anchorOffset < cursor.focusOffset
                  ? cursor.anchorOffset
                  : cursor.focusOffset);
        handler.state.preeditLocalOffset = initialOffset;
        handler.state.lastSyncedText = handler.getCurrentFragmentText() ?? '';
        final parentId = doc.findParentCached(fragId);
        handler.state.preeditContainerId = parentId ?? '';
        handler.state.justCommittedComposition = false;
      }
      handler.state.isComposing = true;

      if (rawPreedit.isNotEmpty) {
        final preeditText = handler.extractPreeditText(value);
        if (preeditText.isNotEmpty) {
          handler.state.preeditText = preeditText;
          handler.state.composingRange = value.composing;
          handler.state.preeditCaretOffset = value.selection.isValid
              ? (value.selection.extentOffset - rawStart).clamp(
                  0,
                  preeditText.length,
                )
              : preeditText.length;

          cursor.imeComposing = true;
          cursor.imeComposingStart = handler.state.preeditLocalOffset;
        }
      }

      doc.selectionManager.clear();
      handler.invalidatePreeditRender();
      return;
    }

    final fragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    final currentText = handler.getCurrentFragmentText() ?? '';

    // -------------------------------------------------------------------------
    // 2. Post-Commit Platform Buffer Sync Guard
    // -------------------------------------------------------------------------
    if (handler.state.justCommittedComposition) {
      if (!value.composing.isValid) {
        handler.state.justCommittedComposition = false;
        handler.state.lastSyncedText =
            handler.getCurrentFragmentText() ?? value.text;
        handler.syncImeBufferToFragment();
        return;
      }
    }

    // -------------------------------------------------------------------------
    // 3. Composition Transition / Commit
    // -------------------------------------------------------------------------
    if (handler.state.isComposing) {
      if (value.text.isNotEmpty) {
        final (prefix, suffix) = handler.getParagraphPrefixAndSuffix();
        final prefixPos = prefix.isNotEmpty ? value.text.indexOf(prefix) : 0;
        final suffixPos = suffix.isNotEmpty
            ? handler.findSuffixPos(value.text, suffix)
            : value.text.length;
        if (prefixPos != -1 &&
            suffixPos != -1 &&
            suffixPos >= prefixPos + prefix.length) {
          final extracted = value.text.substring(
            prefixPos + prefix.length,
            suffixPos,
          );
          final current = handler.getCurrentFragmentText() ?? '';
          if (extracted.isNotEmpty &&
              extracted != current &&
              !current.contains(extracted)) {
            final cleaned =
                (handler.state.preeditText.isNotEmpty &&
                    extracted.trim() == handler.state.preeditText.trim())
                ? handler.state.preeditText
                : extracted.trim();
            if (cleaned.isNotEmpty) {
              handler.state.preeditText = handler.sanitizeUtf16(cleaned);
            }
          }
        }
      }
      final textToCommit = handler.state.preeditText;
      if (textToCommit.isNotEmpty) {
        handler.commitPreedit(textToCommit);
      } else {
        handler.resetComposition();
      }
      doc.selectionManager.clear();
      handler.invalidatePreeditRender();
      if (!value.composing.isValid) {
        handler.state.lastSyncedText = value.text;
        handler.syncImeBufferToFragment();
        return;
      }
    }

    // -------------------------------------------------------------------------
    // 4. Non-Composing Text Edits (Typing, Selection Replace, Deletion)
    // -------------------------------------------------------------------------
    final oldText = currentText;
    final newText = value.text;

    if (newText != oldText) {
      if (!cursor.isCollapsed) {
        doc.saveState(description: 'Replace selection', forceNewAction: false);
        handler.executeBackspace();
        doc.selectionManager.clear();
        final inserted = handler.computeInsertedText(oldText, newText);
        if (inserted.isNotEmpty) {
          handler.insertFinalizedText(inserted);
        }
        handler.syncImeBufferToFragment();
        return;
      } else {
        doc.saveState(description: 'Text edit', forceNewAction: false);
        final inserted = handler.computeInsertedText(oldText, newText);
        if (inserted.isNotEmpty) {
          handler.insertFinalizedText(inserted);
        }
        doc.selectionManager.clear();
        handler.syncImeBufferToFragment();
        return;
      }
    }

    doc.selectionManager.clear();
    handler.syncImeBufferToFragment();
  }

  /// Processes [TextEditingDelta] list updates on Linux platform.
  void updateEditingValueWithDeltas(
    List<TextEditingDelta> deltas,
    FluentTextInputHandler handler,
  ) {
    final doc = handler.document;
    if (doc == null || handler.state.updatingSelf) return;

    if (handler.state.justCommittedComposition) {
      handler.state.justCommittedComposition = false;
      handler.state.lastSyncedText = handler.getCurrentFragmentText() ?? '';
      handler.syncImeBufferToFragment();
      return;
    }

    final bool batchEndsComposing =
        deltas.length > 1 &&
        deltas.last is TextEditingDeltaNonTextUpdate &&
        !(deltas.last as TextEditingDeltaNonTextUpdate).composing.isValid;

    for (final delta in deltas) {
      // -----------------------------------------------------------------------
      // 1. DELETION HANDLING
      // -----------------------------------------------------------------------
      if (delta is TextEditingDeltaDeletion ||
          (delta is TextEditingDeltaReplacement &&
              delta.replacementText.isEmpty)) {
        doc.saveState(description: 'Delete', forceNewAction: false);

        // FIX: durante la composizione IME il testo di preedit non è
        // mai scritto realmente in node.text (è overlay, tracciato via
        // preeditText/composingRange). Una Deletion ricevuta mentre
        // isComposing è true riporta un range relativo al buffer
        // interno del motore IME (che include la preview), non al
        // documento reale: applicarla a node.text cancellava
        // caratteri veri adiacenti al cursore invece di limitarsi ad
        // annullare/chiudere la composizione.
        if (handler.state.isComposing) {
          handler.resetComposition();
          doc.selectionManager.clear();
          handler.invalidatePreeditRender();
          doc.selectionManager.clear();
          handler.syncImeBufferToFragment();
          return;
        }

        if (!doc.cursor.isCollapsed) {
          handler.executeBackspace();
          doc.selectionManager.clear();
        } else {
          final fragId = doc.cursor.focusId.isNotEmpty
              ? doc.cursor.focusId
              : doc.cursor.anchorId;
          final node = doc.nodeById(fragId);

          final deletionRange = delta is TextEditingDeltaDeletion
              ? delta.deletedRange
              : (delta as TextEditingDeltaReplacement).replacedRange;

          if (node is Fragment &&
              deletionRange.isValid &&
              deletionRange.start < deletionRange.end) {
            // FIX: clamp sia start che end sulla lunghezza reale del
            // fragment, e calcola `count` dai valori clampati. Prima
            // `count` usava deletionRange.end - deletionRange.start
            // (non clampati) mentre il cursore veniva spostato su
            // safeEnd (clampato): se il delta riportato dal motore IME
            // era "stale" rispetto al contenuto attuale del nodo,
            // il loop eseguiva troppi executeBackspace(), cancellando
            // testo oltre l'intervallo richiesto.
            final safeStart = deletionRange.start.clamp(0, node.text.length);
            final safeEnd = deletionRange.end.clamp(0, node.text.length);

            if (safeStart < safeEnd) {
              doc.cursor.moveTo(fragId, safeEnd);

              final count = safeEnd - safeStart;
              for (var i = 0; i < count; i++) {
                handler.executeBackspace();
              }
            } else {
              handler.executeBackspace();
            }
          } else {
            handler.executeBackspace();
          }
        }
        doc.selectionManager.clear();
        handler.syncImeBufferToFragment();
        return;
      }

      // -----------------------------------------------------------------------
      // 2. INSERTION HANDLING
      // -----------------------------------------------------------------------
      if (delta is TextEditingDeltaInsertion) {
        doc.saveState(description: 'Type', forceNewAction: false);

        if (delta.composing.isValid &&
            delta.composing.start < delta.composing.end) {
          final wasComposing = handler.state.isComposing;
          if (!doc.cursor.isCollapsed && !wasComposing) {
            handler.executeBackspace();
            doc.selectionManager.clear();
          }

          final fragId = doc.cursor.focusId.isNotEmpty
              ? doc.cursor.focusId
              : doc.cursor.anchorId;

          handler.state.isComposing = true;
          handler.state.preeditFragmentId = fragId;

          final fullText = delta.oldText.replaceRange(
            delta.insertionOffset,
            delta.insertionOffset,
            delta.textInserted,
          );
          final composingStart = delta.composing.start.clamp(
            0,
            fullText.length,
          );
          final composingEnd = delta.composing.end.clamp(0, fullText.length);
          handler.state.preeditText = fullText.substring(
            composingStart,
            composingEnd,
          );
          handler.state.composingRange = delta.composing;

          handler.state.preeditLocalOffset = doc.cursor.focusOffset;
          final parentId = doc.findParentCached(fragId);
          handler.state.preeditContainerId = parentId ?? '';
          doc.cursor.imeComposing = true;
          doc.cursor.imeComposingStart = handler.state.preeditLocalOffset;
          doc.selectionManager.clear();

          if (batchEndsComposing) {
            handler.commitIfComposing();
          } else {
            handler.invalidatePreeditRender();
          }
          return;
        }

        if (handler.state.isComposing) {
          handler.resetComposition();
          doc.selectionManager.clear();
          handler.invalidatePreeditRender();
        }

        if (!doc.cursor.isCollapsed) {
          handler.executeBackspace();
          doc.selectionManager.clear();
        }

        handler.insertFinalizedText(delta.textInserted);
        doc.selectionManager.clear();
        handler.syncImeBufferToFragment();
        return;
      }

      // -----------------------------------------------------------------------
      // 3. REPLACEMENT HANDLING
      // -----------------------------------------------------------------------
      if (delta is TextEditingDeltaReplacement) {
        doc.saveState(description: 'Replace', forceNewAction: false);

        final wasComposing = handler.state.isComposing;
        if (!doc.cursor.isCollapsed && !wasComposing) {
          handler.executeBackspace();
          doc.selectionManager.clear();
        }

        final fragId = doc.cursor.focusId.isNotEmpty
            ? doc.cursor.focusId
            : doc.cursor.anchorId;
        final node = doc.nodeById(fragId);

        if (delta.composing.isValid &&
            delta.composing.start < delta.composing.end) {
          handler.state.isComposing = true;
          handler.state.preeditFragmentId = fragId;
          final parentId = doc.findParentCached(fragId);
          handler.state.preeditContainerId = parentId ?? '';
          final cStart = delta.composing.start.clamp(
            0,
            delta.replacementText.length,
          );
          final cEnd = delta.composing.end.clamp(
            0,
            delta.replacementText.length,
          );
          handler.state.preeditText = cStart < cEnd
              ? delta.replacementText.substring(cStart, cEnd)
              : delta.replacementText;
          handler.state.composingRange = delta.composing;
          handler.state.preeditLocalOffset = doc.cursor.focusOffset;
          doc.cursor.imeComposing = true;
          doc.cursor.imeComposingStart = handler.state.preeditLocalOffset;
          doc.selectionManager.clear();
          if (batchEndsComposing) {
            handler.commitIfComposing();
          } else {
            handler.invalidatePreeditRender();
          }
          return;
        }

        if (handler.state.isComposing) {
          var textToCommit = delta.replacementText.isNotEmpty
              ? delta.replacementText
              : handler.state.preeditText;
          final (prefix, _) = handler.getParagraphPrefixAndSuffix();
          if (prefix.isNotEmpty && textToCommit.startsWith(prefix)) {
            final extracted = handler.extractPreeditText(
              TextEditingValue(
                text: delta.replacementText,
                composing: delta.composing,
              ),
            );
            if (extracted.isNotEmpty) {
              textToCommit = extracted;
            }
          }
          // FIX: usare commitPreedit invece di resetComposition() +
          // insertFinalizedText(). Era l'unico percorso di chiusura
          // composizione a non usare commitPreedit (usato invece nel
          // ramo equivalente di updateEditingValue e nella sezione 3
          // non-delta). resetComposition() da solo non riallinea il
          // cursore/l'intervallo di preedit tracciato prima
          // dell'inserimento, causando un disallineamento che porta
          // a cancellare caratteri successivi al testo committato.
          doc.selectionManager.clear();
          handler.invalidatePreeditRender();
          if (textToCommit.isNotEmpty) {
            handler.commitPreedit(textToCommit);
          } else {
            handler.resetComposition();
          }
          doc.selectionManager.clear();
          handler.syncImeBufferToFragment();
          return;
        }

        if (!doc.cursor.isCollapsed) {
          handler.executeBackspace();
          doc.selectionManager.clear();
          if (delta.replacementText.isNotEmpty) {
            handler.insertFinalizedText(delta.replacementText);
          }
        } else if (node is Fragment &&
            delta.replacedRange.isValid &&
            delta.replacedRange.start < delta.replacedRange.end) {
          final currentText = node.text;
          final safeStart = delta.replacedRange.start.clamp(
            0,
            currentText.length,
          );
          final safeEnd = delta.replacedRange.end.clamp(0, currentText.length);
          if (safeStart < safeEnd) {
            doc.cursor.moveTo(fragId, safeEnd);
            final count = safeEnd - safeStart;
            for (var i = 0; i < count; i++) {
              handler.executeBackspace();
            }
          }
          if (delta.replacementText.isNotEmpty) {
            handler.insertFinalizedText(delta.replacementText);
          }
        } else {
          if (delta.replacementText.isNotEmpty) {
            handler.insertFinalizedText(delta.replacementText);
          }
        }
        doc.selectionManager.clear();
        handler.syncImeBufferToFragment();
        return;
      }

      // -----------------------------------------------------------------------
      // 4. NON-TEXT UPDATE HANDLING
      // -----------------------------------------------------------------------
      if (delta is TextEditingDeltaNonTextUpdate) {
        if (handler.state.isComposing &&
            (!delta.composing.isValid ||
                delta.composing.start >= delta.composing.end)) {
          if (deltas.any(
            (d) =>
                d is TextEditingDeltaInsertion ||
                d is TextEditingDeltaReplacement,
          )) {
            continue;
          }
          handler.commitIfComposing();
          doc.selectionManager.clear();
          handler.syncImeBufferToFragment();
          return;
        }
        if (doc.cursor.imeComposing && !handler.state.isComposing) {
          doc.cursor.imeComposing = false;
          doc.cursor.imeComposingStart = 0;
          doc.selectionManager.clear();
        }
        continue;
      }
    }
  }

  /// Calculates current [TextEditingValue] for Linux desktop clients.
  TextEditingValue? getCurrentTextEditingValue(FluentTextInputHandler handler) {
    final doc = handler.document;
    final text = handler.getCurrentFragmentText() ?? '';
    if (doc == null) {
      return TextEditingValue(
        text: text,
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    final cursor = doc.cursor;
    final isSingleFragSelection =
        !cursor.isCollapsed && cursor.anchorId == cursor.focusId;
    final isMultiFragSelection =
        !cursor.isCollapsed && cursor.anchorId != cursor.focusId;
    final offset = handler.getCursorOffsetInFragment();

    final TextSelection selection;
    if (isSingleFragSelection) {
      selection = TextSelection(
        baseOffset: cursor.anchorOffset.clamp(0, text.length),
        extentOffset: cursor.focusOffset.clamp(0, text.length),
      );
    } else if (isMultiFragSelection) {
      selection = TextSelection(baseOffset: 0, extentOffset: text.length);
    } else {
      selection = TextSelection.collapsed(offset: offset);
    }

    return TextEditingValue(
      text: text,
      selection: selection,
      composing:
          handler.state.isComposing && handler.state.composingRange.isValid
          ? handler.state.composingRange
          : TextRange.empty,
    );
  }

  /// Synchronizes engine text editing state for Linux clients.
  void syncImeBufferToFragment(FluentTextInputHandler handler) {
    if (handler.connectionManager.connection == null ||
        !handler.connectionManager.connection!.attached) {
      return;
    }
    if (handler.state.isComposing) return;
    final doc = handler.document;
    if (doc == null) return;
    final currentFragId = doc.cursor.focusId.isNotEmpty
        ? doc.cursor.focusId
        : doc.cursor.anchorId;

    if (currentFragId != handler.state.lastSyncedFragmentId) {
      handler.resetPlatformBuffer();
    }
    handler.state.lastSyncedFragmentId = currentFragId;

    final text = handler.getCurrentFragmentText();
    if (text == null) {
      handler.resetPlatformBuffer();
      return;
    }
    final cursor = doc.cursor;
    final isSingleFragSelection =
        !cursor.isCollapsed && cursor.anchorId == cursor.focusId;
    final isMultiFragSelection =
        !cursor.isCollapsed && cursor.anchorId != cursor.focusId;
    final offset = handler.getCursorOffsetInFragment();

    final syncedText = text;
    final syncedOffset = offset.clamp(0, syncedText.length);
    final TextSelection syncedSelection;
    if (isSingleFragSelection) {
      syncedSelection = TextSelection(
        baseOffset: cursor.anchorOffset.clamp(0, syncedText.length),
        extentOffset: cursor.focusOffset.clamp(0, syncedText.length),
      );
    } else if (isMultiFragSelection) {
      syncedSelection = TextSelection(
        baseOffset: 0,
        extentOffset: syncedText.length,
      );
    } else {
      syncedSelection = TextSelection.collapsed(offset: syncedOffset);
    }

    handler.state.prevSelectionKey =
        '${syncedSelection.baseOffset}:${syncedSelection.extentOffset}';

    final wasUpdatingSelf = handler.state.updatingSelf;
    handler.state.updatingSelf = true;
    try {
      handler.connectionManager.connection!.setEditingState(
        TextEditingValue(
          text: syncedText,
          selection: syncedSelection,
          composing: TextRange.empty,
        ),
      );
      handler.state.lastSyncedText = syncedText;
    } finally {
      handler.state.updatingSelf = wasUpdatingSelf;
    }
  }
}
