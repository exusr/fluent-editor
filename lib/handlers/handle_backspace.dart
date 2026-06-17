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
/// 5. If lineStart is pressed: delete to beginning of line
/// 6. If ctrl is pressed: delete the previous word
/// 7. Otherwise: delete the previous character in the fragment
bool executeHandleBackspace(FluentDocument document, {bool ctrl = false, bool lineStart = false}) {
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

  // Case 1.5: If lineStart is pressed, delete to beginning of current line
  if (lineStart) {
    return _handleDeleteToLineStart(document);
  }

  // Case 1.6: If ctrl is pressed, delete the previous word
  if (ctrl) {
    return _handleDeleteWord(document);
  }

  // Find the fragment and the current container
  // Case 2a: If cursor is on a HorizontalRule, remove it.
  final currentNode = document.nodeById(cursor.anchorId);
  if (currentNode is HorizontalRule) {
    final targetStop = _findPreviousStop(
      root, cursor.anchorId, 0,
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
    final prevStop = _findPreviousStop(
      root, cursor.anchorId, 0,
      cachedStops: document.caretStops,
      cachedLines: document.logicalLines,
    );
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
    final targetStop = _findPreviousStop(
      root, cursor.anchorId, 0,
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

  // Case 3: If we're at the start of the container (offset == 0)
  // handle the merge with the previous node or outdent for lists
  if (cursor.anchorOffset == 0) {
    return _handleBackspaceAtStart(document, container, currentFrag);
  }

  // Case 4: Normal character deletion
  // Use grapheme-aware offset to handle emoji (surrogate pairs) correctly
  final newOffset = FragmentOperations.getPreviousGraphemeOffset(currentFrag.text, cursor.anchorOffset);
  final deleteCount = cursor.anchorOffset - newOffset;
  FragmentOperations.deleteTextInFragment(currentFrag, newOffset, count: deleteCount);

  // If the fragment became empty, remove it (and any empty parent Links)
  // so it doesn't block future backspace navigation.
  if (currentFrag.text.isEmpty) {
    // Use the logical container (e.g. Paragraph) to decide whether we
    // can safely remove the empty fragment.  A fragment that is the only
    // child of a style wrapper must still be removed when other fragments
    // exist elsewhere in the paragraph.
    final flat = _flattenInlineChildren(container);
    if (flat.length > 1) {
      int fragIdx = -1;
      for (int i = 0; i < flat.length; i++) {
        if (flat[i].id == currentFrag.id) {
          fragIdx = i;
          break;
        }
      }

      final parent = findParent(root, currentFrag);
      removeNode(root, currentFrag);
      // Clean up empty Links / style wrappers that might have contained
      // this fragment.
      _cleanupEmptyInlineParents(root, parent);

      if (fragIdx > 0) {
        // Move cursor to the end of the nearest non-empty predecessor.
        for (int i = fragIdx - 1; i >= 0; i--) {
          final prev = flat[i];
          if (prev is Fragment && prev is! InlineContainerNode && prev.text.isNotEmpty) {
            cursor.moveTo(prev.id, prev.text.length);
            break;
          }
        }
      } else if (fragIdx == 0 && flat.length > 1) {
        // First fragment removed: move cursor to the start of what is now
        // the first fragment (offset 0 triggers container-boundary logic
        // on the next backspace if the user keeps deleting).
        final next = flat[1];
        if (next is Fragment && next is! InlineContainerNode) {
          cursor.moveTo(next.id, 0);
        }
      }
      document.updateContent();
      return true;
    }
  }

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


  // Guard: if the cursor is already on an empty fragment, remove it and
  // reposition before calling moveLeft (empty fragments have no caret stops).
  if (currentFrag.text.isEmpty) {
    final flat = _flattenInlineChildren(container);
    if (flat.length > 1) {
      int fragIdx = -1;
      for (int i = 0; i < flat.length; i++) {
        if (flat[i].id == currentFrag.id) {
          fragIdx = i;
          break;
        }
      }
      final parent = findParent(root, currentFrag);
      removeNode(root, currentFrag);
      _cleanupEmptyInlineParents(root, parent);
      if (fragIdx > 0) {
        for (int i = fragIdx - 1; i >= 0; i--) {
          final prev = flat[i];
          if (prev is Fragment && prev is! InlineContainerNode && prev.text.isNotEmpty) {
            cursor.moveTo(prev.id, prev.text.length);
            document.updateContent();
            return true;
          }
        }
      }
      if (fragIdx >= 0 && fragIdx < flat.length - 1) {
        final next = flat[fragIdx + 1];
        if (next is Fragment && next is! InlineContainerNode) {
          cursor.moveTo(next.id, 0);
          document.updateContent();
          return true;
        }
      }
      document.updateContent();
      return true;
    }
  }

  // Find the previous node in the document
  final prevStop = moveLeft(
    root,
    CaretStop(cursor.anchorId, cursor.anchorOffset),
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );


  if (prevStop.position == null) {
    // We're at the start of the document, nothing to do
    return false;
  }

  final prevFrag = document.nodeById(prevStop.position!.fragmentId) as Fragment?;
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
    // Use the flat child order to find the immediate predecessor of
    // currentFrag.  moveLeft skips empty fragments, so we walk the
    // raw children ourselves to clean up any invisible empties.
    final flat = _flattenInlineChildren(container);
    int currentIdx = -1;
    for (int i = 0; i < flat.length; i++) {
      if (flat[i].id == currentFrag.id) {
        currentIdx = i;
        break;
      }
    }
    if (currentIdx > 0) {
      int targetIdx = currentIdx - 1;
      while (targetIdx >= 0) {
        final candidate = flat[targetIdx];
        if (candidate is Fragment && candidate is! InlineContainerNode) {
          if (candidate.text.isEmpty) {
            final parent = findParent(root, candidate);
            removeNode(root, candidate);
            _cleanupEmptyInlineParents(root, parent);
            targetIdx--;
            continue;
          }
          // Delete the last character of the first non-empty predecessor.
          // Use grapheme-aware deletion to handle emoji correctly
          final deletePos = FragmentOperations.getPreviousGraphemeOffset(candidate.text, candidate.text.length);
          final deleteCount = candidate.text.length - deletePos;
          FragmentOperations.deleteTextInFragment(candidate, deletePos, count: deleteCount);

          if (candidate.text.isEmpty) {
            // Find where to place the cursor AFTER removing the empty
            // candidate, so we never point to a stale fragment id.
            String? newCursorFragId;
            int newCursorOffset = 0;
            for (int j = targetIdx - 1; j >= 0; j--) {
              final pred = flat[j];
              if (pred is Fragment &&
                  pred is! InlineContainerNode &&
                  pred.text.isNotEmpty) {
                newCursorFragId = pred.id;
                newCursorOffset = pred.text.length;
                break;
              }
            }
            final parent = findParent(root, candidate);
            removeNode(root, candidate);
            _cleanupEmptyInlineParents(root, parent);
            if (newCursorFragId != null) {
              cursor.moveTo(newCursorFragId, newCursorOffset);
            }
            // If no predecessor exists, cursor stays at its current
            // position (offset 0 of currentFrag).
          } else {
            cursor.moveTo(candidate.id, deletePos);
          }
          document.updateContent();
          return true;
        }
        break; // Non-fragment child blocks further traversal
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

/// Returns the "flat" list of children of [container] in reading order,
/// expanding Links (transparent) into their fragments.
List<FNode> _flattenInlineChildren(InlineContainerNode container) {
  final out = <FNode>[];
  for (final child in container.getChildren()) {
    if (child is Link) {
      for (final inner in child.getChildren()) {
        out.add(inner);
      }
    } else {
      out.add(child);
    }
  }
  return out;
}

/// Removes empty Links and other inline wrappers that no longer contain
/// any text fragments after a deletion.
void _cleanupEmptyInlineParents(Root root, FNode? node) {
  if (node == null) return;
  if (node is Link && node.getChildren().isEmpty) {
    final parent = findParent(root, node);
    removeNode(root, node);
    if (parent != null) _cleanupEmptyInlineParents(root, parent);
  }
}

/// Finds the previous stop in the document.
CaretStop? _findPreviousStop(
  Root root,
  String fragmentId,
  int offset, {
  List<CaretStop>? cachedStops,
  List<LogicalLine>? cachedLines,
}) {
  final result = moveLeft(
    root,
    CaretStop(fragmentId, offset),
    stops: cachedStops,
    cachedLines: cachedLines,
  );
  return result.position;
}

/// Deletes from the current cursor position back to the start of the
/// current logical line (macOS Cmd+Backspace behaviour).
bool _handleDeleteToLineStart(FluentDocument document) {
  final cursor = document.cursor;
  final current = CaretStop(cursor.anchorId, cursor.anchorOffset);

  // Find the logical line that contains the current cursor position.
  for (final line in document.logicalLines) {
    final idx = line.stops.indexWhere(
      (s) => s.fragmentId == current.fragmentId && s.offset == current.offset,
    );
    if (idx >= 0) {
      final firstStop = line.stops.first;
      cursor.focusTo(firstStop.fragmentId, firstStop.offset);
      executeHandleReplaceSelection('', document);
      return true;
    }
  }

  // Fallback: nothing to delete
  return false;
}

/// Handles deleting the previous word (Ctrl+Backspace).
/// Uses the same logic as moveWordLeft to find the word boundary.
bool _handleDeleteWord(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;

  final current = CaretStop(cursor.anchorId, cursor.anchorOffset);
  final wordLeftResult = moveWordLeft(
    root, current,
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );

  if (wordLeftResult.position == null) {
    // At the start of the document, nothing to delete
    return false;
  }

  final targetStop = wordLeftResult.position!;
  final currentFrag = document.nodeById(cursor.anchorId) as Fragment?;
  if (currentFrag == null) return false;

  // Temporarily set the cursor focus to the target position to create a selection
  cursor.focusTo(targetStop.fragmentId, targetStop.offset);

  // Delete the word by replacing the selection with an empty string
  executeHandleReplaceSelection('', document);
  
  return true;
}