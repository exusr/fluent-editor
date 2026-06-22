import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/utils/node_operations.dart';

/// Handles the Delete key.
///
/// Supported behaviors:
/// 1. If there's an active selection: delete the selection
/// 2. If cursor is at the end of a container: merge with the next node
/// 3. If cursor is on an image: remove the image
/// 4. If ctrl is pressed: delete the next word
/// 5. Otherwise: delete the next character in the fragment
bool executeHandleDelete(FluentDocument document, {bool ctrl = false}) {
  final root = document.content;
  final cursor = document.cursor;

  if (deleteSelectionIfExists(document)) return true;

  if (ctrl) {
    return deleteWordHelper(document, forward: true);
  }

  final currentNode = document.nodeById(cursor.anchorId);
  if (currentNode is HorizontalRule) {
    return removeNodeAndReposition(document, currentNode, forward: true);
  }

  final currentFrag = resolveFragmentFromCursor(currentNode, cursor.anchorOffset);
  if (currentFrag == null) return false;

  final container = findLogicalContainer(root, cursor.anchorId);
  if (container == null) return false;

  if (currentFrag is FluentImage) {
    return removeNodeAndReposition(document, currentFrag, forward: true);
  }

  if (cursor.anchorOffset >= currentFrag.text.length) {
    return _handleDeleteAtEnd(document, container, currentFrag);
  }

  FragmentOperations.deleteTextInFragment(currentFrag, cursor.anchorOffset, count: 1);

  cursor.moveTo(currentFrag.id, cursor.anchorOffset);

  notifyTextMutation(document, container, currentFrag.id, cursor.anchorOffset, -1);

  document.updateContent();
  return true;
}

/// Handles delete when the cursor is at the end of a fragment.
bool _handleDeleteAtEnd(
  FluentDocument document,
  InlineContainerNode container,
  Fragment currentFrag,
) {
  final root = document.content;
  final cursor = document.cursor;

  final nextStop = moveRight(
    root,
    CaretStop(cursor.anchorId, cursor.anchorOffset),
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );

  if (nextStop.position == null) {
    return false;
  }

  final nextFrag = document.nodeById(nextStop.position!.fragmentId) as Fragment?;
  if (nextFrag == null) return false;

  final nextContainer = findLogicalContainer(root, nextStop.position!.fragmentId);
  if (nextContainer == null) return false;

  if ((nextContainer as FNode).id == (container as FNode).id) {
    if (nextFrag.text.isNotEmpty) {
      FragmentOperations.deleteTextInFragment(nextFrag, 0, count: 1);
      cursor.moveTo(currentFrag.id, currentFrag.text.length);
    } else {
      final siblings = container.getChildren();
      if (siblings.length > 1) {
        removeNode(root, nextFrag);
        cursor.moveTo(currentFrag.id, currentFrag.text.length);
      }
    }
    document.updateContent();
    return true;
  }

  if (nextContainer is FluentImage || nextContainer is HorizontalRule) {
    removeNode(root, nextContainer as FNode);
    document.updateContent();
    return true;
  }

  return _mergeWithNextContainer(document, container, currentFrag, nextContainer, nextFrag);
}

/// Merges the current container with the next one.
bool _mergeWithNextContainer(
  FluentDocument document,
  InlineContainerNode currentContainer,
  Fragment currentFrag,
  InlineContainerNode nextContainer,
  Fragment nextFrag,
) {
  final root = document.content;
  final cursor = document.cursor;

  if (nextContainer is FluentList) {
    cursor.moveTo(nextFrag.id, 0);
    document.updateContent();
    return true;
  }

  if (nextContainer is FluentCell) {
    clearCellKeepingEmptyFragment(nextContainer, root);
    cursor.moveTo(currentFrag.id, currentFrag.text.length);
    document.updateContent();
    return true;
  }
  if (nextContainer is FluentRow || nextContainer is FluentTable) {
    cursor.moveTo(currentFrag.id, currentFrag.text.length);
    document.updateContent();
    return true;
  }

  if (isContainerEmpty(currentContainer)) {
    removeNode(root, currentContainer as FNode);
    moveCursorToFirstFragment(cursor, nextContainer);
    document.updateContent();
    return true;
  }

  final currentChildrenBefore = currentContainer.getChildren().toList();
  final junctionFrag = (currentChildrenBefore.isNotEmpty &&
          currentChildrenBefore.last is Fragment &&
          currentChildrenBefore.last is! InlineContainerNode)
      ? currentChildrenBefore.last as Fragment
      : null;

  moveInlineChildren(root, nextContainer, currentContainer);

  removeNode(root, nextContainer as FNode);

  mergeAtJunction(document, currentContainer, junctionFrag, currentChildrenBefore.length);
  return true;
}
