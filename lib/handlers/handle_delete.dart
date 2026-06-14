import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

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

  // Case 1: If there's an active selection, delete it
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
    // Delete the selection by replacing it with an empty string
    executeHandleReplaceSelection('', document);
    return true;
  }

  // Case 1.5: If ctrl is pressed, delete the next word
  if (ctrl) {
    return _handleDeleteNextWord(document);
  }

  // Find the fragment and the current container
  final currentNode = document.nodeById(cursor.anchorId);
  if (currentNode is HorizontalRule) {
    final targetStop = _findNextStop(
      root, cursor.anchorId, 1,
      cachedStops: document.caretStops,
      cachedLines: document.logicalLines,
    );
    removeNode(root, currentNode);
    if (targetStop != null) {
      cursor.moveTo(targetStop.fragmentId, targetStop.offset);
    }
    document.updateContent();
    return true;
  }

  // Resolve the actual Fragment from the cursor anchor
  Fragment? currentFrag;
  if (currentNode is Fragment) {
    currentFrag = currentNode;
  } else if (currentNode is InlineContainerNode) {
    final containerNode = currentNode as InlineContainerNode;
    final children = containerNode.getChildren();
    if (cursor.anchorOffset >= 0 && cursor.anchorOffset < children.length) {
      final child = children[cursor.anchorOffset];
      if (child is Fragment) currentFrag = child;
    }
    if (currentFrag == null) {
      for (final child in children) {
        if (child is Fragment) {
          currentFrag = child;
          break;
        }
      }
    }
  }
  if (currentFrag == null) return false;

  final container = findLogicalContainer(root, cursor.anchorId);
  if (container == null) return false;

  // Case 2b: If it's an image, remove the entire node
  if (currentFrag is FluentImage) {
    final targetStop = _findNextStop(
      root, cursor.anchorId, 1,
      cachedStops: document.caretStops,
      cachedLines: document.logicalLines,
    );
    removeNode(root, currentFrag);
    if (targetStop != null) {
      cursor.moveTo(targetStop.fragmentId, targetStop.offset);
    }
    document.updateContent();
    return true;
  }

  // Case 3: If we're at the end of the fragment
  if (cursor.anchorOffset >= currentFrag.text.length) {
    return _handleDeleteAtEnd(document, container, currentFrag);
  }

  // Case 4: Normal character deletion
  FragmentOperations.deleteTextInFragment(currentFrag, cursor.anchorOffset, count: 1);

  // Update the cursor (stays at the same position)
  cursor.moveTo(currentFrag.id, cursor.anchorOffset);

  // Notify comment system of the text mutation
  if (container is Paragraph) {
    final globalOffset = document.getGlobalOffsetInParagraph(
      container.id,
      currentFrag.id,
      cursor.anchorOffset,
    );
    if (globalOffset != null) {
      document.notifyTextMutation(container.id, globalOffset, -1);
    }
  }

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

  // Find the next stop in the document
  final nextStop = moveRight(
    root,
    CaretStop(cursor.anchorId, cursor.anchorOffset),
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );

  if (nextStop.position == null) {
    // We're at the end of the document, nothing to do
    return false;
  }

  final nextFrag = document.nodeById(nextStop.position!.fragmentId) as Fragment?;
  if (nextFrag == null) return false;

  final nextContainer = findLogicalContainer(root, nextStop.position!.fragmentId);
  if (nextContainer == null) return false;

  // If the next fragment belongs to the same container, delete the first character
  if ((nextContainer as FNode).id == (container as FNode).id) {
    if (nextFrag.text.isNotEmpty) {
      FragmentOperations.deleteTextInFragment(nextFrag, 0, count: 1);
      cursor.moveTo(currentFrag.id, currentFrag.text.length);
    } else {
      // nextFrag is empty: remove it if it's not the only child
      final siblings = container.getChildren();
      if (siblings.length > 1) {
        removeNode(root, nextFrag);
        cursor.moveTo(currentFrag.id, currentFrag.text.length);
      }
    }
    document.updateContent();
    return true;
  }

  // If the next element is a block-level image or HR, remove it
  if (nextContainer is FluentImage || nextContainer is HorizontalRule) {
    removeNode(root, nextContainer as FNode);
    document.updateContent();
    return true;
  }

  // General case: merge the current container with the next one
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

  // If the next container is a list, we cannot merge
  if (nextContainer is FluentList) {
    // Simply move the cursor to the start of the next one
    cursor.moveTo(nextFrag.id, 0);
    document.updateContent();
    return true;
  }

  // If the next container is a table/row/cell, clear the current cell
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

  // If the current container is empty, remove it
  final currentChildrenList = currentContainer.getChildren();
  if (currentChildrenList.isEmpty ||
      (currentChildrenList.length == 1 &&
       currentChildrenList.first is Fragment &&
       (currentChildrenList.first as Fragment).text.isEmpty)) {
    removeNode(root, currentContainer as FNode);
    // Position the cursor at the start of the next container
    final nextChildren = nextContainer.getChildren();
    if (nextChildren.isNotEmpty) {
      final first = nextChildren.first;
      if (first is Link && first.fragments.isNotEmpty) {
        final linkFrag = first.fragments.first as Fragment;
        cursor.moveTo(linkFrag.id, 0);
      } else if (first is Fragment) {
        cursor.moveTo(first.id, 0);
      }
    }
    document.updateContent();
    return true;
  }

  // Snapshot of the junction position before moving children
  final currentChildrenBefore = currentContainer.getChildren().toList();
  final junctionFrag = (currentChildrenBefore.isNotEmpty &&
          currentChildrenBefore.last is Fragment &&
          currentChildrenBefore.last is! InlineContainerNode)
      ? currentChildrenBefore.last as Fragment
      : null;

  // Move all children from the next container to the current one
  for (final child in nextContainer.getChildren().toList()) {
    if (child is Fragment || child is Link) {
      removeNode(root, child);
      appendChild(currentContainer as FNode, child);
    }
  }

  // Remove the next container (now empty)
  removeNode(root, nextContainer as FNode);

  // Merge at the junction point only if both boundaries are plain Fragment
  final currentChildren = currentContainer.getChildren();
  final firstMoved = currentChildren.length > currentChildrenBefore.length
      ? currentChildren[currentChildrenBefore.length]
      : null;

  if (junctionFrag != null &&
      firstMoved != null &&
      firstMoved is Fragment &&
      firstMoved is! InlineContainerNode) {
    // Calculate the new cursor position (at the end of the junction fragment)
    final newCursorOffset = junctionFrag.text.length;

    // Merge adjacent fragments
    FragmentOperations.mergeFragments(junctionFrag, firstMoved);
    removeNode(root, firstMoved);

    cursor.moveTo(junctionFrag.id, newCursorOffset);
  } else if (junctionFrag != null) {
    // The first moved child is a Link or non-plain-fragment: cursor at end of junction
    cursor.moveTo(junctionFrag.id, junctionFrag.text.length);
  } else if (currentChildren.isNotEmpty) {
    // No previous fragment: cursor at the start of the first moved child
    final first = currentChildren.first;
    if (first is Link && first.fragments.isNotEmpty) {
      final linkFrag = first.fragments.first as Fragment;
      cursor.moveTo(linkFrag.id, 0);
    } else if (first is Fragment) {
      cursor.moveTo(first.id, 0);
    }
  }

  // Recalculate the indices of all modified lists
  recalculateListIndices(root);

  document.updateContent();
  return true;
}

/// Finds the next stop in the document.
CaretStop? _findNextStop(
  Root root,
  String fragmentId,
  int offset, {
  List<CaretStop>? cachedStops,
  List<LogicalLine>? cachedLines,
}) {
  final result = moveRight(
    root,
    CaretStop(fragmentId, offset),
    stops: cachedStops,
    cachedLines: cachedLines,
  );
  return result.position;
}

/// Handles deleting the next word (Ctrl+Delete).
/// Uses the same logic as moveWordRight to find the word boundary.
bool _handleDeleteNextWord(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;

  final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
  final wordRightResult = moveWordRight(
    root, current,
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );

  if (wordRightResult.position == null) {
    // At the end of the document, nothing to delete
    return false;
  }

  final targetStop = wordRightResult.position!;
  final currentFrag = document.nodeById(cursor.anchorId) as Fragment?;
  if (currentFrag == null) return false;

  // Temporarily set the cursor focus to the target position to create a selection
  cursor.focusTo(targetStop.fragmentId, targetStop.offset);

  // Delete the word by replacing the selection with an empty string
  executeHandleReplaceSelection('', document);
  
  return true;
}
