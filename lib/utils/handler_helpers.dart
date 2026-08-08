import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Resolves the current cursor selection using cached stops and lines.
/// Returns null if the cursor is collapsed or the selection is invalid.
/// Caches the result on the document so multiple widgets in the same
/// cursor-change cycle reuse the same ResolvedSelection.
ResolvedSelection? resolveSelectionFromCursor(FluentDocument document) {
  final cursor = document.cursor;
  final key = '${cursor.anchorId}:${cursor.anchorOffset}:'
      '${cursor.focusId}:${cursor.focusOffset}';
  if (key == document.cachedSelectionKey) {
    return document.cachedSelection as ResolvedSelection?;
  }
  final result = resolveSelection(
    document.content,
    cursor.anchorId,
    cursor.anchorOffset,
    cursor.focusId,
    cursor.focusOffset,
    cachedStops: document.caretStops,
    cachedLines: document.logicalLines,
    document: document,
  );
  document.cachedSelectionKey = key;
  document.cachedSelection = result;
  return result;
}

/// Recalculates list indices and triggers a content update.
void recalculateAndUpdate(FluentDocument document) {
  recalculateListIndices(document.content);
  document.updateContent();
}

/// Saves undo state, removes [node] from the document, and updates content.
void saveAndDeleteNode(FluentDocument document, FNode node, {required String description}) {
  if (document.registry.dispatchDeleteNode(document, node)) return;
  document.saveState(description: description, forceNewAction: true);
  removeNode(document.content, node);
  document.updateContent();
}

/// Splits fragments at selection boundaries, then calls [modify] on each
/// leaf fragment in the resulting range (skipping FluentImage).
/// Returns the first and last modified fragments, or nulls if none modified.
({Fragment? firstModified, Fragment? lastModified}) splitAndApplyToLeaves(
  FluentDocument document,
  ResolvedSelection selection, {
  required void Function(Fragment leaf) modify,
}) {
  Fragment? firstModified;
  Fragment? lastModified;

  for (final node in selection.nodes) {
    final container = node.container;

    final startParent = findParentCached(document, node.startFragment);
    final endParent   = findParentCached(document, node.endFragment);

    late Fragment actualStartFrag;
    late Fragment actualEndFrag;

    if (node.startFragment.id == node.endFragment.id) {
      final frag = node.startFragment;
      final len = frag.text.length;
      var start = node.startOffset.clamp(0, len);
      var end = node.endOffset.clamp(0, len);
      if (start > end) {
        final tmp = start;
        start = end;
        end = tmp;
      }

      if (start == end) {
        actualStartFrag = frag;
        actualEndFrag   = frag;
      } else if (start > 0 && end < len) {
        final before = frag.text.substring(0, start);
        final mid    = frag.text.substring(start, end);
        final after  = frag.text.substring(end);
        frag.text = before;
        final midFrag = FragmentOperations.cloneFragment(frag, text: mid);
        if (startParent != null) insertAfter(startParent, frag, midFrag);
        if (after.isNotEmpty && startParent != null) {
          final afterFrag = FragmentOperations.cloneFragment(frag, text: after);
          insertAfter(startParent, midFrag, afterFrag);
        }
        actualStartFrag = midFrag;
        actualEndFrag   = midFrag;
      } else if (start > 0) {
        final before = frag.text.substring(0, start);
        final after  = frag.text.substring(start);
        frag.text = before;
        final newFrag = FragmentOperations.cloneFragment(frag, text: after);
        if (startParent != null) insertAfter(startParent, frag, newFrag);
        actualStartFrag = newFrag;
        actualEndFrag   = newFrag;
      } else if (end < len) {
        final selected = frag.text.substring(0, end);
        final after    = frag.text.substring(end);
        frag.text = selected;
        final afterFrag = FragmentOperations.cloneFragment(frag, text: after);
        if (startParent != null) insertAfter(startParent, frag, afterFrag);
        actualStartFrag = frag;
        actualEndFrag   = frag;
      } else {
        actualStartFrag = frag;
        actualEndFrag   = frag;
      }
    } else {
      final first = node.startFragment;
      final firstLen = first.text.length;
      final sOffset = node.startOffset.clamp(0, firstLen);
      if (sOffset > 0 && sOffset < firstLen) {
        final before = first.text.substring(0, sOffset);
        final after  = first.text.substring(sOffset);
        first.text = before;
        final newFrag = FragmentOperations.cloneFragment(first, text: after);
        if (startParent != null) insertAfter(startParent, first, newFrag);
        actualStartFrag = newFrag;
      } else {
        actualStartFrag = first;
      }

      final last = node.endFragment;
      final lastLen = last.text.length;
      final eOffset = node.endOffset.clamp(0, lastLen);
      if (eOffset > 0 && eOffset < lastLen) {
        final selected = last.text.substring(0, eOffset);
        final after    = last.text.substring(eOffset);
        last.text = selected;
        final afterFrag = FragmentOperations.cloneFragment(last, text: after);
        if (endParent != null) insertAfter(endParent, last, afterFrag);
        actualEndFrag = last;
      } else {
        actualEndFrag = last;
      }
    }

    final leaves = FragmentOperations.collectLeafFragments(container as FNode);
    int startIdx = leaves.indexWhere((l) => l.id == actualStartFrag.id);
    int endIdx = leaves.indexWhere((l) => l.id == actualEndFrag.id);

    if (node.startFragment.id != node.endFragment.id) {
      final sOffset = node.startOffset.clamp(0, node.startFragment.text.length);
      final eOffset = node.endOffset.clamp(0, node.endFragment.text.length);
      // If we didn't split but the selection starts at the end of the start fragment, skip it.
      if (sOffset >= node.startFragment.text.length && actualStartFrag.id == node.startFragment.id) {
        startIdx++;
      }
      // If we didn't split but the selection ends at the start of the end fragment, skip it.
      if (eOffset <= 0 && actualEndFrag.id == node.endFragment.id) {
        endIdx--;
      }
    }

    if (startIdx <= endIdx && startIdx >= 0 && endIdx < leaves.length) {
      for (int i = startIdx; i <= endIdx; i++) {
        final leaf = leaves[i];
        if (leaf is! FluentImage) {
          if (leaf.styles?.contains(document.suggestionStyleHook.deletionTag) != true) {
            modify(leaf);
            firstModified ??= leaf;
            lastModified = leaf;
          }
        }
      }
    }
  }

  return (firstModified: firstModified, lastModified: lastModified);
}

/// Removes [node] from the tree and repositions the cursor to the
/// adjacent caret stop (previous when [forward] is false, next when true).
/// Calls [document.updateContent] and returns true.
bool removeNodeAndReposition(
  FluentDocument document,
  FNode node, {
  bool forward = false,
}) {
  if (document.registry.dispatchDeleteNode(document, node)) return true;

  document.saveState(description: 'Delete node', forceNewAction: true);

  final root = document.content;
  final cursor = document.cursor;
  final stop = forward
      ? moveRight(
          root,
          CaretStop(cursor.anchorId, 1),
          stops: document.caretStops,
          cachedLines: document.logicalLines,
        ).position
      : moveLeft(
          root,
          CaretStop(cursor.anchorId, 0),
          stops: document.caretStops,
          cachedLines: document.logicalLines,
        ).position;
  removeNode(root, node);
  if (stop != null) {
    cursor.moveTo(stop.fragmentId, stop.offset);
  }
  document.updateContent();
  return true;
}

/// Moves [cursor] to the start (offset 0) of the first fragment child of
/// [container]. Handles Link transparency.
void moveCursorToFirstFragment(Cursor cursor, InlineContainerNode container) {
  final children = container.getChildren();
  if (children.isEmpty) return;
  final first = children.first;
  if (first is Link && first.fragments.isNotEmpty) {
    cursor.moveTo((first.fragments.first as Fragment).id, 0);
  } else if (first is Fragment) {
    cursor.moveTo(first.id, 0);
  }
}

/// Moves [cursor] to the end (text.length) of the last fragment child of
/// [container]. Handles Link transparency.
void moveCursorToLastFragment(Cursor cursor, InlineContainerNode container) {
  final children = container.getChildren();
  if (children.isEmpty) return;
  final last = children.last;
  if (last is Link && last.fragments.isNotEmpty) {
    final f = last.fragments.last as Fragment;
    cursor.moveTo(f.id, f.text.length);
  } else if (last is Fragment) {
    cursor.moveTo(last.id, last.text.length);
  }
}

/// When the cursor still points to a removed fragment, tries moveLeft
/// then moveRight to find the nearest valid caret stop.
void fallbackRepositionCursor(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;
  final leftStop = moveLeft(
    root,
    CaretStop(cursor.anchorId, cursor.anchorOffset),
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );
  if (leftStop.position != null) {
    cursor.moveTo(leftStop.position!.fragmentId, leftStop.position!.offset);
    return;
  }
  final rightStop = moveRight(
    root,
    CaretStop(cursor.anchorId, cursor.anchorOffset),
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );
  if (rightStop.position != null) {
    cursor.moveTo(rightStop.position!.fragmentId, rightStop.position!.offset);
  }
}

/// Deletes a word in the given direction by creating a temporary selection
/// from the current cursor position to the word boundary, then replacing
/// it with an empty string.
bool deleteWordHelper(FluentDocument document, {required bool forward}) {
  final root = document.content;
  final cursor = document.cursor;
  final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
  final result = forward
      ? moveWordRight(root, current,
          stops: document.caretStops, cachedLines: document.logicalLines)
      : moveWordLeft(root, current,
          stops: document.caretStops, cachedLines: document.logicalLines);
  if (result.position == null) return false;
  cursor.focusTo(result.position!.fragmentId, result.position!.offset);
  executeHandleReplaceSelection('', document);
  return true;
}

/// Merges children at the junction point after moving children from one
/// container to another. Handles fragment merging, cursor positioning,
/// list index recalculation, and content update.
///
/// [targetContainer] is the container that received the moved children.
/// [junctionFrag] is the last fragment of the target container before the
/// move (captured by the caller). [childrenBeforeCount] is the number of
/// children [targetContainer] had before the move.
void mergeAtJunction(
  FluentDocument document,
  InlineContainerNode targetContainer,
  Fragment? junctionFrag,
  int childrenBeforeCount,
) {
  final root = document.content;
  final cursor = document.cursor;

  final children = targetContainer.getChildren();
  final firstMoved = children.length > childrenBeforeCount
      ? children[childrenBeforeCount]
      : null;

  if (junctionFrag != null &&
      firstMoved != null &&
      firstMoved is Fragment &&
      firstMoved is! InlineContainerNode) {
    final newCursorOffset = junctionFrag.text.length;
    FragmentOperations.mergeFragments(junctionFrag, firstMoved);
    removeNode(root, firstMoved);
    cursor.moveTo(junctionFrag.id, newCursorOffset);
  } else if (junctionFrag != null) {
    cursor.moveTo(junctionFrag.id, junctionFrag.text.length);
  } else if (children.isNotEmpty) {
    moveCursorToFirstFragment(cursor, targetContainer);
  }

  recalculateAndUpdate(document);
}

/// If there's an active selection, deletes it by replacing with empty string.
/// Returns true if a selection was deleted, false otherwise.
bool deleteSelectionIfExists(FluentDocument document) {
  final selection = resolveSelectionFromCursor(document);
  if (selection != null) {
    executeHandleReplaceSelection('', document);
    return true;
  }
  return false;
}

/// Notifies the comment system of a text mutation when the container is a
/// Paragraph. No-op for other container types.
void notifyTextMutation(
  FluentDocument document,
  InlineContainerNode container,
  String fragmentId,
  int offset,
  int delta,
) {
  if (container is Paragraph) {
    final globalOffset = document.getGlobalOffsetInParagraph(
      (container as FNode).id,
      fragmentId,
      offset,
    );
    if (globalOffset != null) {
      document.notifyTextMutation((container as FNode).id, globalOffset, delta);
    }
  }
}

/// Generic helper for applying a style property to the selection or cursor.
/// When a selection exists, [modifyLeaf] is applied to each leaf fragment
/// and the cursor moves to the end of the modified range.
/// When collapsed, [setPending] stores the value for subsequently typed text.
bool applyStyleProperty<T>(
  FluentDocument document,
  T value, {
  required void Function(Fragment leaf, T value) modifyLeaf,
  required void Function(FluentDocument document, T value) setPending,
}) {
  final selection = resolveSelectionFromCursor(document);
  if (selection != null) {
    final cursor = document.cursor;
    final result = splitAndApplyToLeaves(
      document,
      selection,
      modify: (leaf) => modifyLeaf(leaf, value),
    );
    if (result.lastModified != null) {
      cursor.moveTo(result.lastModified!.id, result.lastModified!.text.length);
    }
    setPending(document, value);
    document.updateContent();
    return true;
  }
  setPending(document, value);
  document.updateContent();
  return true;
}
