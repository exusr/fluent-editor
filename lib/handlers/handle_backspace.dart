import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';

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

  if (deleteSelectionIfExists(document)) return true;

  if (lineStart) {
    return _handleDeleteToLineStart(document);
  }

  if (ctrl) {
    return deleteWordHelper(document, forward: false);
  }

  final currentNode = document.nodeById(cursor.anchorId);
  if (currentNode is HorizontalRule) {
    return removeNodeAndReposition(document, currentNode);
  }

  final currentFrag = resolveFragmentFromCursor(currentNode, cursor.anchorOffset);
  if (currentFrag == null) return false;

  final container = document.findLogicalContainerCached(cursor.anchorId);
  if (container == null) return false;

  if (container is Paragraph && container.text.isEmpty &&
      findAncestor<FluentCell>(root, container as FNode) == null) {
    final prevStop = moveLeft(
      root, CaretStop(cursor.anchorId, 0),
      stops: document.caretStops,
      cachedLines: document.logicalLines,
    ).position;
    if (prevStop != null) {
      removeNode(root, container as FNode);
      cursor.moveTo(prevStop.fragmentId, prevStop.offset);
      document.updateContent();
      return true;
    }
    return false;
  }

  if (currentFrag is FluentImage) {
    return removeNodeAndReposition(document, currentFrag);
  }

  if (findAncestor<FluentCell>(root, currentFrag) != null &&
      currentFrag.text.isNotEmpty &&
      currentFrag.text.replaceAll('\u200B', '').isEmpty) {
    return true;
  }

  if (cursor.anchorOffset == 0) {
    return _handleBackspaceAtStart(document, container, currentFrag);
  }

  int newOffset = FragmentOperations.getPreviousGraphemeOffsetSkippingZWS(currentFrag.text, cursor.anchorOffset);
  final deleteCount = cursor.anchorOffset - newOffset;

  final cellParent = findAncestor<FluentCell>(root, currentFrag);

  FragmentOperations.deleteTextInFragment(currentFrag, newOffset, count: deleteCount);

  if (cellParent != null && currentFrag.text.isEmpty) {
    currentFrag.text = '\u200B';
    cursor.moveTo(currentFrag.id, 0);
    document.updateContent();
    return true;
  }

  if (currentFrag.text.isEmpty) {
    if (_removeEmptyFragmentAndReposition(document, container, currentFrag)) {
      document.updateContent();
      return true;
    }
  }

  cursor.moveTo(currentFrag.id, newOffset);

  notifyTextMutation(document, container, currentFrag.id, newOffset, -1);

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

  if (currentFrag.text.isEmpty) {
    if (_removeEmptyFragmentAndReposition(document, container, currentFrag)) {
      document.updateContent();
      return true;
    }

    final flat = flattenInlineChildren(container);
    if (flat.length == 1) {
      if (findAncestor<FluentCell>(root, container as FNode) != null) {
        return true;
      }
      final prevStop = moveLeft(
        root,
        CaretStop(cursor.anchorId, cursor.anchorOffset),
        stops: document.caretStops,
        cachedLines: document.logicalLines,
      );
      if (prevStop.position == null) {
        _removeFragAndUpdate(document, root, currentFrag);
        return true;
      }
      final prevFrag = document.nodeById(prevStop.position!.fragmentId) as Fragment?;
      if (prevFrag == null) {
        _removeFragAndUpdate(document, root, currentFrag);
        return true;
      }
      final prevContainer = document.findLogicalContainerCached(prevStop.position!.fragmentId);
      if (prevContainer == null) {
        _removeFragAndUpdate(document, root, currentFrag);
        return true;
      }
      _removeFrag(root, currentFrag);
      return _mergeContainers(document, prevContainer, container, prevFrag, currentFrag);
    }
  }

  final prevStop = moveLeft(
    root,
    CaretStop(cursor.anchorId, cursor.anchorOffset),
    stops: document.caretStops,
    cachedLines: document.logicalLines,
  );

  if (prevStop.position == null) {
    return false;
  }

  final prevFrag = document.nodeById(prevStop.position!.fragmentId) as Fragment?;
  if (prevFrag == null) return false;

  final prevContainer = document.findLogicalContainerCached(prevStop.position!.fragmentId);
  if (prevContainer == null) return false;

  if (cursor.anchorOffset == 0) {
    final ancestorItem = findAncestor<ListItem>(root, container as FNode);
    if (ancestorItem != null && ancestorItem.children.isNotEmpty &&
        ancestorItem.children.first.id == (container as FNode).id) {
      return _handleListItemOutdent(document, ancestorItem, prevContainer);
    }
  }

  if ((prevContainer as FNode).id == (container as FNode).id) {
    final flat = flattenInlineChildren(container);
    int currentIdx = flat.indexWhere((f) => f.id == currentFrag.id);
    if (currentIdx > 0) {
      int targetIdx = currentIdx - 1;
      while (targetIdx >= 0) {
        final candidate = flat[targetIdx];
        if (candidate is Fragment && candidate is! InlineContainerNode) {
          if (candidate.text.isEmpty) {
            final parent = findParent(root, candidate);
            removeNode(root, candidate);
            cleanupEmptyInlineParents(root, parent);
            targetIdx--;
            continue;
          }
          int deletePos = FragmentOperations.getPreviousGraphemeOffsetSkippingZWS(candidate.text, candidate.text.length);
          final deleteCount = candidate.text.length - deletePos;
          FragmentOperations.deleteTextInFragment(candidate, deletePos, count: deleteCount);

          if (candidate.text.isEmpty) {
            final predFrag = findPredecessorFragment(flat, targetIdx);
            final newCursorFragId = predFrag?.id;
            int newCursorOffset = predFrag?.text.length ?? 0;
            final parent = findParent(root, candidate);
            removeNode(root, candidate);
            cleanupEmptyInlineParents(root, parent);
            if (newCursorFragId != null) {
              cursor.moveTo(newCursorFragId, newCursorOffset);
            }
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

  if (prevContainer is FluentImage || prevContainer is HorizontalRule) {
    removeNode(root, prevContainer as FNode);
    document.updateContent();
    return true;
  }

  return _mergeContainers(document, prevContainer, container, prevFrag, currentFrag);
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

  final listParent = findParent(root, currentItem);
  if (listParent == null || listParent is! FluentList) {
    return _mergeContainers(document, prevContainer, currentItem, null, null);
  }

  final itemIndex = listParent.items.indexWhere((item) => item.id == currentItem.id);
  if (itemIndex < 0) return false;

  final sublists = currentItem.children
      .whereType<FluentList>()
      .toList();

  if (itemIndex > 0) {
    final prevItem = listParent.items[itemIndex - 1];
    return _mergeListItems(document, listParent, prevItem, currentItem, sublists);
  }

  final newParagraph = outdentListItemToParagraph(root, listParent, currentItem);
  if (newParagraph == null) return false;

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

  final currentChildren = currentItem.children.toList();

  final currentFirstParagraph = findFirstParagraph(currentItem);
  final prevLastParagraph = findLastParagraph(prevItem);

  removeNode(root, currentItem);

  String cursorFragId = '';
  int cursorOffset = 0;

  if (prevLastParagraph != null && currentFirstParagraph != null) {
    final prevFrags = prevLastParagraph.fragments.whereType<Fragment>().toList();
    final currentFrags = currentFirstParagraph.fragments.toList();

    if (prevFrags.isNotEmpty) {
      final lastPrevFrag = prevFrags.last;
      cursorFragId = lastPrevFrag.id;
      cursorOffset = lastPrevFrag.text.length;
    }

    for (final f in currentFrags) {
      removeNode(root, f);
      appendChild(prevLastParagraph, f);
    }

    if (cursorFragId.isEmpty && currentFrags.isNotEmpty && currentFrags.first is Fragment) {
      cursorFragId = currentFrags.first.id;
      cursorOffset = 0;
    }

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
    removeNode(root, currentFirstParagraph);
    appendChild(prevItem, currentFirstParagraph);
    final firstFrag = currentFirstParagraph.fragments.firstOrNull;
    if (firstFrag is Fragment) {
      cursorFragId = firstFrag.id;
      cursorOffset = 0;
    }
  }

  for (final c in currentChildren) {
    if (c == currentFirstParagraph) continue;
    if (c is FluentList) {
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

  recalculateAndUpdate(document);
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

  if (prevContainer is FluentList) {
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }

  if (prevContainer is FluentCell) {
    clearCellKeepingEmptyFragment(prevContainer, root);
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }
  if (prevContainer is FluentRow || prevContainer is FluentTable) {
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }

  if (currentContainer is FluentCell) {
    clearCellKeepingEmptyFragment(currentContainer, root);
    if (prevFrag != null) {
      cursor.moveTo(prevFrag.id, prevFrag.text.length);
    }
    document.updateContent();
    return true;
  }

  if (isContainerEmpty(currentContainer)) {
    removeNode(root, currentContainer as FNode);
    moveCursorToLastFragment(cursor, prevContainer);
    document.updateContent();
    return true;
  }

  final prevChildrenBefore = prevContainer.getChildren().toList();
  final junctionFrag = (prevChildrenBefore.isNotEmpty &&
          prevChildrenBefore.last is Fragment &&
          prevChildrenBefore.last is! InlineContainerNode)
      ? prevChildrenBefore.last as Fragment
      : null;

  moveInlineChildren(root, currentContainer, prevContainer);

  removeNode(root, currentContainer as FNode);

  mergeAtJunction(document, prevContainer, junctionFrag, prevChildrenBefore.length);
  return true;
}

/// Removes an empty [currentFrag] from [container] when there are siblings,
/// repositions the cursor to the predecessor or successor, and returns true.
/// Returns false if the container has only one child (caller handles that case).
bool _removeEmptyFragmentAndReposition(
  FluentDocument document,
  InlineContainerNode container,
  Fragment currentFrag,
) {
  final root = document.content;
  final cursor = document.cursor;

  final flat = flattenInlineChildren(container);
  if (flat.length <= 1) return false;

  int fragIdx = flat.indexWhere((f) => f.id == currentFrag.id);
  final parent = findParent(root, currentFrag);
  removeNode(root, currentFrag);
  cleanupEmptyInlineParents(root, parent);

  if (fragIdx > 0) {
    final pred = findPredecessorFragment(flat, fragIdx);
    if (pred != null) {
      cursor.moveTo(pred.id, pred.text.length);
      return true;
    }
  }

  if (fragIdx >= 0 && fragIdx < flat.length - 1) {
    final next = flat[fragIdx + 1];
    if (next is Fragment && next is! InlineContainerNode) {
      cursor.moveTo(next.id, 0);
      return true;
    }
  }

  if (cursor.anchorId == currentFrag.id) {
    fallbackRepositionCursor(document);
  }
  return true;
}

/// Removes [frag] from the tree, cleans up empty inline parents,
/// and calls [document.updateContent].
void _removeFragAndUpdate(FluentDocument document, Root root, Fragment frag) {
  _removeFrag(root, frag);
  document.updateContent();
}

/// Removes [frag] from the tree and cleans up empty inline parents.
void _removeFrag(Root root, Fragment frag) {
  final parent = findParent(root, frag);
  removeNode(root, frag);
  cleanupEmptyInlineParents(root, parent);
}

/// Deletes from the current cursor position back to the start of the
/// current logical line (macOS Cmd+Backspace behaviour).
bool _handleDeleteToLineStart(FluentDocument document) {
  final cursor = document.cursor;
  final current = CaretStop(cursor.anchorId, cursor.anchorOffset);

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

  return false;
}

