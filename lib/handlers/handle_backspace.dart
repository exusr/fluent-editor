import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Handles the Backspace key.
///
/// Supported behaviors:
/// 1. If there's an active selection: delete the selection
/// 2. If cursor is at the start of a ListItem: outdent (remove from list)
/// 3. If cursor is at the start of another node: merge with the previous node
/// 4. If cursor is on an image: remove the image
/// 5. If ctrl is pressed: delete the previous word
/// 6. Otherwise: delete the previous character in the fragment
bool executeHandleBackspace(FluentDocument document, {bool ctrl = false}) {
  final root = document.content;
  final cursor = document.cursor;

  // Case 1: If there's an active selection, delete it
  final selection = resolveSelection(
    root,
    cursor.anchorId,
    cursor.anchorOffset,
    cursor.focusId,
    cursor.focusOffset,
  );

  if (selection != null) {
    // Delete the selection by replacing it with an empty string
    executeHandleReplaceSelection('', document);
    return true;
  }

  // Case 1.5: If ctrl is pressed, delete the previous word
  if (ctrl) {
    return _handleDeleteWord(document);
  }

  // Find the fragment and the current container
  // Case 2a: If cursor is on a HorizontalRule, remove it.
  final currentNode = findById(root, cursor.anchorId);
  if (currentNode is HorizontalRule) {
    final targetStop = _findPreviousStop(root, cursor.anchorId, 0);
    removeNode(root, currentNode);
    if (targetStop != null) {
      cursor.moveTo(targetStop.fragmentId, targetStop.offset);
    }
    document.updateContent();
    return true;
  }

  // Resolve the actual Fragment from the cursor anchor (which may be a
  // Paragraph, Image, HorizontalRule, or Fragment itself).
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

  // Special case: cursor is inside an empty paragraph.
  // Remove the paragraph and move the cursor to the end of the previous one.
  if (container is Paragraph && container.text.isEmpty) {
    final prevStop = _findPreviousStop(root, cursor.anchorId, 0);
    if (prevStop != null) {
      removeNode(root, container as FNode);
      cursor.moveTo(prevStop.fragmentId, prevStop.offset);
      document.updateContent();
      return true;
    }
    // At the very start of the document: nothing to merge with.
    return false;
  }

  // Case 2b: If it's an image, remove the entire node.
  // The cursor should be positioned on the stop that precedes the image
  // (offset 0 of the image → moveLeft gives the true previous).
  if (currentFrag is FluentImage) {
    final targetStop = _findPreviousStop(root, cursor.anchorId, 0);
    removeNode(root, currentFrag);
    if (targetStop != null) {
      cursor.moveTo(targetStop.fragmentId, targetStop.offset);
    }
    document.updateContent();
    return true;
  }

  // Case 3: If we're at the start of the container (offset == 0)
  // handle the merge with the previous node or outdent for lists
  if (cursor.anchorOffset == 0) {
    return _handleBackspaceAtStart(document, container, currentFrag);
  }

  // Case 4: Normal character deletion
  final newOffset = cursor.anchorOffset - 1;
  FragmentOperations.deleteTextInFragment(currentFrag, newOffset, count: 1);

  // Update the cursor
  cursor.moveTo(currentFrag.id, newOffset);

  // Notify comment system of the text mutation.
  if (container is Paragraph) {
    final globalOffset = document.getGlobalOffsetInParagraph(
      container.id,
      currentFrag.id,
      newOffset,
    );
    if (globalOffset != null) {
      document.notifyTextMutation(container.id, globalOffset, -1);
    }
  }

  document.updateContent();
  return true;
}

/// Handles backspace when the cursor is at the start of a container.
bool _handleBackspaceAtStart(
  FluentDocument document,
  InlineContainerNode container,
  Fragment currentFrag,
) {
  final root = document.content;
  final cursor = document.cursor;

  // Find the previous node in the document
  final prevStop = moveLeft(root, CaretStop(
    cursor.anchorId,
    cursor.anchorOffset,
  ));

  if (prevStop.position == null) {
    // We're at the start of the document, nothing to do
    return false;
  }

  final prevFrag = findById(root, prevStop.position!.fragmentId) as Fragment?;
  if (prevFrag == null) return false;

  final prevContainer = findLogicalContainer(root, prevStop.position!.fragmentId);
  if (prevContainer == null) return false;

  // Case ListItem: outdent (remove from list if we're at the start of the first Paragraph)
  // With the new structure, container is the Paragraph inside the ListItem.
  if (cursor.anchorOffset == 0) {
    final ancestorItem = _findAncestorListItem(root, container as FNode);
    if (ancestorItem != null && ancestorItem.children.isNotEmpty &&
        ancestorItem.children.first.id == (container as FNode).id) {
      return _handleListItemOutdent(document, ancestorItem, prevContainer);
    }
  }

  // Case: the previous fragment belongs to the same container (e.g., cursor
  // at offset 0 of a non-first fragment within the same Paragraph, or
  // at the start of a fragment after a Link). We must not merge containers:
  // just delete the last character of the previous fragment.
  if ((prevContainer as FNode).id == (container as FNode).id) {
    final prevOffset = prevStop.position!.offset;
    if (prevOffset > 0) {
      final deletePos = (prevFrag is! InlineContainerNode && prevFrag.text.isNotEmpty)
          ? prevFrag.text.length - 1
          : prevOffset - 1;
      FragmentOperations.deleteTextInFragment(prevFrag, deletePos, count: 1);
      cursor.moveTo(prevFrag.id, deletePos);
    } else {
      // prevFrag is empty: remove it if it's not the only child
      final siblings = container.getChildren();
      if (siblings.length > 1) {
        removeNode(root, prevFrag);
        cursor.moveTo(currentFrag.id, 0);
      }
    }
    document.updateContent();
    return true;
  }

  // If the previous element is a block-level image or HR, remove it
  // directly without attempting a merge between incompatible containers.
  if (prevContainer is FluentImage || prevContainer is HorizontalRule) {
    removeNode(root, prevContainer as FNode);
    document.updateContent();
    return true;
  }

  // General case: merge the containers
  return _mergeContainers(document, prevContainer, container, prevFrag, currentFrag);
}

/// Climbs up looking for a ListItem ancestor.
ListItem? _findAncestorListItem(Root root, FNode node) {
  FNode? current = node;
  while (current != null) {
    if (current is ListItem) return current;
    current = findParent(root, current);
  }
  return null;
}

/// Handles the outdent of a ListItem.
///
/// If it's not the first item in the list: merge with the previous one.
/// If it's the first item: transform to paragraph and promote sublists.
bool _handleListItemOutdent(
  FluentDocument document,
  ListItem currentItem,
  InlineContainerNode prevContainer,
) {
  final root = document.content;

  // Find the parent FluentList
  final listParent = findParent(root, currentItem);
  if (listParent == null || listParent is! FluentList) {
    // Not in a list, normal behavior
    return _mergeContainers(document, prevContainer, currentItem, null, null);
  }

  // Find the index of the current item in the list
  final itemIndex = listParent.items.indexWhere((item) => item.id == currentItem.id);
  if (itemIndex < 0) return false;

  // Extract sublists from children before removing the item
  final sublists = currentItem.children
      .whereType<FluentList>()
      .toList();

  // If NOT the first item: merge with the previous one
  if (itemIndex > 0) {
    final prevItem = listParent.items[itemIndex - 1];
    return _mergeListItems(document, listParent, prevItem, currentItem, sublists);
  }

  // It's the first item: normal outdent (transform to paragraph)
  final newParagraph = outdentListItemToParagraph(root, listParent, currentItem);
  if (newParagraph == null) return false;

  // Position the cursor at the start of the new paragraph
  final cursor = document.cursor;
  if (newParagraph.fragments.isNotEmpty) {
    final firstFrag = newParagraph.fragments.first as Fragment;
    cursor.moveTo(firstFrag.id, 0);
  }

  document.updateContent();
  return true;
}

/// Merges a ListItem with the previous one in the same list.
///
/// The first Paragraph of the currentItem is merged with the last Paragraph of
/// the prevItem (concatenating fragments). The other children of the currentItem
/// (images, tables, sublists) are moved as children of the prevItem.
bool _mergeListItems(
  FluentDocument document,
  FluentList listParent,
  ListItem prevItem,
  ListItem currentItem,
  List<FluentList> sublists,
) {
  final root = document.content;
  final cursor = document.cursor;

  // Snapshot of children before modifying the tree
  final currentChildren = currentItem.children.toList();

  // Find the first Paragraph of the currentItem (will be merged with prevItem)
  Paragraph? currentFirstParagraph;
  for (final c in currentChildren) {
    if (c is Paragraph) {
      currentFirstParagraph = c;
      break;
    }
  }

  // Find the last Paragraph of the prevItem (target of the merge)
  Paragraph? prevLastParagraph;
  for (final c in prevItem.children.reversed) {
    if (c is Paragraph) {
      prevLastParagraph = c;
      break;
    }
  }

  // Remove the current item from the list
  removeNode(root, currentItem);

  // Point where to position the cursor after the merge
  String cursorFragId = '';
  int cursorOffset = 0;

  if (prevLastParagraph != null && currentFirstParagraph != null) {
    // Concatenate the fragments of the first current Paragraph at the end of prevLastParagraph
    final prevFrags = prevLastParagraph.fragments.whereType<Fragment>().toList();
    final currentFrags = currentFirstParagraph.fragments.toList();

    // Junction position: at the end of the last fragment of the prev, or
    // at the start of the first fragment of the current if prev was empty.
    if (prevFrags.isNotEmpty) {
      final lastPrevFrag = prevFrags.last;
      cursorFragId = lastPrevFrag.id;
      cursorOffset = lastPrevFrag.text.length;
    }

    // Move all fragments of the currentFirstParagraph to the prevLastParagraph
    for (final f in currentFrags) {
      removeNode(root, f);
      appendChild(prevLastParagraph, f);
    }

    // If prev was empty, position the cursor at the start of the first moved fragment
    if (cursorFragId.isEmpty && currentFrags.isNotEmpty && currentFrags.first is Fragment) {
      cursorFragId = currentFrags.first.id;
      cursorOffset = 0;
    }

    // Merge adjacent fragments with same attributes (best-effort: only the two at the junction point)
    if (prevFrags.isNotEmpty && currentFrags.isNotEmpty) {
      final lastPrevFrag = prevFrags.last;
      final firstNewFrag = currentFrags.first;
      if (firstNewFrag is Fragment) {
        final mergeOffset = lastPrevFrag.text.length;
        FragmentOperations.mergeFragments(lastPrevFrag, firstNewFrag);
        removeNode(root, firstNewFrag);
        cursorFragId = lastPrevFrag.id;
        cursorOffset = mergeOffset;
      }
    }
  } else if (currentFirstParagraph != null) {
    // prevItem had no paragraphs: append the currentFirstParagraph as a child
    removeNode(root, currentFirstParagraph);
    appendChild(prevItem, currentFirstParagraph);
    final firstFrag = currentFirstParagraph.fragments.firstOrNull;
    if (firstFrag is Fragment) {
      cursorFragId = firstFrag.id;
      cursorOffset = 0;
    }
  }

  // Move the other children of the currentItem (excluding the first Paragraph already handled)
  // as children of the prevItem.
  for (final c in currentChildren) {
    if (c == currentFirstParagraph) continue;
    if (c is FluentList) {
      // Sublists are promoted to the listParent level (after prevItem)
      removeNode(root, c);
      final prevIndex = listParent.items.indexOf(prevItem);
      if (prevIndex >= 0) {
        for (var i = 0; i < c.items.length; i++) {
          listParent.items.insert(prevIndex + 1 + i, c.items[i]);
        }
      }
    } else {
      removeNode(root, c);
      appendChild(prevItem, c);
    }
  }

  if (cursorFragId.isNotEmpty) {
    cursor.moveTo(cursorFragId, cursorOffset);
  }

  // Recalculate the indices of all modified lists
  recalculateListIndices(root);

  document.updateContent();
  return true;
}

/// Merges two containers (prevContainer + currentContainer).
bool _mergeContainers(
  FluentDocument document,
  InlineContainerNode prevContainer,
  InlineContainerNode currentContainer,
  Fragment? prevFrag,
  Fragment? currentFrag,
) {
  final root = document.content;
  final cursor = document.cursor;

  // If the previous container is a list, we cannot merge
  if (prevContainer is FluentList) {
    // Simply move the cursor to the end of the previous one
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }

  // If the previous container is a table/row/cell, clear the current cell
  if (prevContainer is FluentCell) {
    clearCellKeepingEmptyFragment(prevContainer, root);
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }
  if (prevContainer is FluentRow || prevContainer is FluentTable) {
    // Look for the first cell or the previous fragment to position the cursor
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }

  // If the current container is a cell, clear it keeping an empty fragment
  if (currentContainer is FluentCell) {
    clearCellKeepingEmptyFragment(currentContainer, root);
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }

  // If the current container is empty, remove it
  final currentChildren = currentContainer.getChildren();
  if (currentChildren.isEmpty ||
      (currentChildren.length == 1 &&
       currentChildren.first is Fragment &&
       (currentChildren.first as Fragment).text.isEmpty)) {
    removeNode(root, currentContainer as FNode);
    // Position the cursor at the end of the previous container
    final prevChildren = prevContainer.getChildren();
    if (prevChildren.isNotEmpty) {
      final last = prevChildren.last;
      if (last is Link && last.fragments.isNotEmpty) {
        final linkFrag = last.fragments.last as Fragment;
        cursor.moveTo(linkFrag.id, linkFrag.text.length);
      } else if (last is Fragment) {
        cursor.moveTo(last.id, last.text.length);
      }
    }
    document.updateContent();
    return true;
  }

  // Snapshot of the junction position before moving children
  final prevChildrenBefore = prevContainer.getChildren().toList();
  final junctionFrag = (prevChildrenBefore.isNotEmpty &&
          prevChildrenBefore.last is Fragment &&
          prevChildrenBefore.last is! InlineContainerNode)
      ? prevChildrenBefore.last as Fragment
      : null;

  // Move all children from the current container to the previous one:
  // plain Fragment and Link (inline container) are transferred entirely.
  for (final child in currentChildren.toList()) {
    if (child is Fragment || child is Link) {
      removeNode(root, child);
      appendChild(prevContainer as FNode, child);
    }
  }

  // Remove the current container (now empty)
  removeNode(root, currentContainer as FNode);

  // Merge at the junction point only if both boundaries are plain Fragment
  final prevChildren = prevContainer.getChildren();
  final firstMoved = prevChildren.length > prevChildrenBefore.length
      ? prevChildren[prevChildrenBefore.length]
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
  } else if (prevChildren.isNotEmpty) {
    // No previous fragment: cursor at the start of the first moved child
    final first = prevChildren.first;
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

/// Finds the previous stop in the document.
CaretStop? _findPreviousStop(Root root, String fragmentId, int offset) {
  final result = moveLeft(root, CaretStop(fragmentId, offset));
  return result.position;
}

/// Handles deleting the previous word (Ctrl+Backspace).
/// Uses the same logic as moveWordLeft to find the word boundary.
bool _handleDeleteWord(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;

  final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
  final wordLeftResult = moveWordLeft(root, current);

  if (wordLeftResult.position == null) {
    // At the start of the document, nothing to delete
    return false;
  }

  final targetStop = wordLeftResult.position!;
  final currentFrag = findById(root, cursor.anchorId) as Fragment?;
  if (currentFrag == null) return false;

  // Temporarily set the cursor focus to the target position to create a selection
  cursor.focusTo(targetStop.fragmentId, targetStop.offset);

  // Delete the word by replacing the selection with an empty string
  executeHandleReplaceSelection('', document);
  
  return true;
}