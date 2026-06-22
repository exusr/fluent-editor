import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Removes [node] from the tree and repositions the cursor to the
/// adjacent caret stop (previous when [forward] is false, next when true).
/// Calls [document.updateContent] and returns true.
bool removeNodeAndReposition(
  FluentDocument document,
  FNode node, {
  bool forward = false,
}) {
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

  recalculateListIndices(root);
  document.updateContent();
}

/// If there's an active selection, deletes it by replacing with empty string.
/// Returns true if a selection was deleted, false otherwise.
bool deleteSelectionIfExists(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;
  final selection = resolveSelection(
    root,
    cursor.anchorId,
    cursor.anchorOffset,
    cursor.focusId,
    cursor.focusOffset,
    cachedStops: document.caretStops,
    cachedLines: document.logicalLines,
  );
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
