// node_operations.dart
//
// PURE utility for tree node operations.
// No dependency on FluentDocument, Cursor or Flutter.
// Each function receives Root (or the necessary subtree) and returns
// a result, never void — so it's testable in isolation.
//
// ORGANIZATION:
//  1. Traversal   — finding nodes in the tree
//  2. Node CRUD   — insertion, removal, substitution of nodes
//  3. Inline      — operations on InlineContainerNode children

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';

// ═══════════════════════════════════════════════════════════════════════
// 1. TRAVERSAL
// ═══════════════════════════════════════════════════════════════════════

/// Returns the direct children of [node] for any type, including
/// Root, FluentList, FluentTable/FluentRow.
/// It's the base function to use everywhere instead of direct getChildren().
List<FNode> childrenOf(FNode node) {
  if (node is Root) return List<FNode>.from(node.nodes);
  if (node is FluentTable) {
    return node.getChildren().cast<FNode>();
  }
  if (node is FluentRow) {
    return node.getChildren().cast<FNode>();
  }
  if (node is FluentList) {
    return node.getChildren().cast<FNode>();
  }
  if (node is InlineContainerNode) {
    return (node as InlineContainerNode).getChildren().cast<FNode>();
  }
  return [];
}

/// Correct version of findRecursive: traverses ALL node types,
/// including Root, FluentList, FluentTable and ListItem with sublists.
///
/// Replaces the old findRecursive in editor_utils.dart that skipped
/// FluentList and FluentTable.
FNode? findNode(FNode root, bool Function(FNode) test) {
  if (test(root)) return root;
  for (final child in childrenOf(root)) {
    final found = findNode(child, test);
    if (found != null) return found;
  }
  return null;
}

/// Finds a node by ID in the entire tree.
/// If [nodeIndex] is provided (e.g. document.nodeIndex), it is used
/// directly for an O(1) lookup instead of a full DFS traversal.
FNode? findById(FNode root, String id, {Map<String, FNode>? nodeIndex}) {
  if (nodeIndex != null) return nodeIndex[id];
  return findNode(root, (n) => n.id == id);
}

/// Finds the direct parent of [target] in the tree with root [root].
/// Returns null if [target] is the root or not found.
FNode? findParent(FNode root, FNode target) {
  for (final child in childrenOf(root)) {
    if (child.id == target.id) return root;
    final found = findParent(child, target);
    if (found != null) return found;
  }
  return null;
}

/// Finds the first InlineContainerNode (Paragraph/ListItem/FluentCell)
/// that contains [fragmentId] as a direct text descendant.
/// Link is transparent: its fragments belong to the parent container.
///
/// If [logicalContainerCache] is provided (e.g. document's internal cache),
/// it is used for an O(1) lookup instead of a full DFS traversal.
InlineContainerNode? findLogicalContainer(
  FNode root,
  String fragmentId, {
  Map<String, InlineContainerNode?>? logicalContainerCache,
}) {
  if (logicalContainerCache != null) {
    return logicalContainerCache[fragmentId];
  }

  InlineContainerNode? search(FNode node, InlineContainerNode? currentContainer) {
    // FluentImage atomic:
    //  - INLINE (inside Paragraph/Link, currentContainer is Paragraph):
    //    it's a fragment of the Paragraph → return the Paragraph.
    //  - BLOCK-LEVEL (parent Root/ListItem/FluentCell, currentContainer
    //    is that "block container"): it's its own logical-line → return
    //    the image itself.
    if (node is FluentImage && node.id == fragmentId) {
      if (currentContainer is Paragraph) return currentContainer;
      return node as InlineContainerNode;
    }
    if (node is HorizontalRule && node.id == fragmentId) {
      return node as InlineContainerNode;
    }
    // Link: transparent, doesn't update currentContainer
    if (node is Link) {
      for (final child in node.getChildren()) {
        final found = search(child, currentContainer);
        if (found != null) return found;
      }
      return null;
    }

    // FluentList / FluentTable: descend without container
    if (node is FluentList || node is FluentTable || node is FluentRow) {
      for (final child in childrenOf(node)) {
        final found = search(child, null);
        if (found != null) return found;
      }
      return null;
    }

    // InlineContainerNode (Paragraph, ListItem, FluentCell): new container
    if (node is InlineContainerNode) {
      final container = node as InlineContainerNode;
      for (final child in container.getChildren()) {
        if (child is FluentList) {
          // Sublists: new container scope
          final found = search(child, null);
          if (found != null) return found;
        } else {
          final found = search(child, container);
          if (found != null) return found;
        }
      }
      return null;
    }

    // Leaf Fragment: check if it's the one searched for
    if (node is Fragment && node.id == fragmentId) {
      return currentContainer;
    }

    return null;
  }

  return search(root, null);
}

/// Returns the path from the tree [root] to [target]
/// as a list of nodes (including root and target).
/// Returns null if not found.
List<FNode>? pathTo(FNode root, FNode target) {
  if (root.id == target.id) return [root];
  for (final child in childrenOf(root)) {
    final sub = pathTo(child, target);
    if (sub != null) return [root, ...sub];
  }
  return null;
}

/// Visits all nodes in DFS pre-order, calling [visitor] on each.
/// If [visitor] returns false, stops the visit.
bool walkTree(FNode root, bool Function(FNode node, FNode? parent) visitor,
    {FNode? parent}) {
  if (!visitor(root, parent)) return false;
  for (final child in childrenOf(root)) {
    if (!walkTree(child, visitor, parent: root)) return false;
  }
  return true;
}

/// Collects all leaf Fragments of the tree in reading order.
List<Fragment> collectAllFragments(FNode root) {
  final result = <Fragment>[];
  walkTree(root, (node, _) {
    if (node is Fragment && node is! InlineContainerNode) {
      result.add(node);
    }
    return true;
  });
  return result;
}

// ═══════════════════════════════════════════════════════════════════════
// 2. NODE CRUD — insertion, removal, substitution in the tree
// ═══════════════════════════════════════════════════════════════════════

/// Returns the mutable list of children of [parent], or null if
/// [parent] doesn't support mutable children directly.
List<FNode>? _mutableChildrenOf(FNode parent) {
  if (parent is Root) return parent.nodes;
  if (parent is FluentList) return parent.getChildren().cast<FNode>();
  if (parent is FluentTable) return parent.getChildren().cast<FNode>();
  if (parent is FluentRow) return parent.getChildren().cast<FNode>();
  if (parent is InlineContainerNode && parent is! FluentImage && parent is! HorizontalRule) {
    return (parent as InlineContainerNode).getChildren().cast<FNode>();
  }
  return null;
}

/// Inserts [newNode] as a child of [parent] after [sibling].
/// Returns false if [sibling] is not a direct child of [parent].
bool insertAfter(FNode parent, FNode sibling, FNode newNode) {
  final children = _mutableChildrenOf(parent);
  if (children == null) return false;
  final idx = children.indexWhere((c) => c.id == sibling.id);
  if (idx < 0) return false;
  children.insert(idx + 1, newNode);
  return true;
}

/// Inserts [newNode] as a child of [parent] before [sibling].
bool insertBefore(FNode parent, FNode sibling, FNode newNode) {
  final children = _mutableChildrenOf(parent);
  if (children == null) return false;
  final idx = children.indexWhere((c) => c.id == sibling.id);
  if (idx < 0) return false;
  children.insert(idx, newNode);
  return true;
}

/// Appends [newNode] as the last child of [parent].
bool appendChild(FNode parent, FNode newNode) {
  final children = _mutableChildrenOf(parent);
  if (children == null) return false;
  children.add(newNode);
  return true;
}

/// Prepends [newNode] as the first child of [parent].
bool prependChild(FNode parent, FNode newNode) {
  final children = _mutableChildrenOf(parent);
  if (children == null) return false;
  children.insert(0, newNode);
  return true;
}

/// Removes [target] from the tree with root [root].
/// Returns false if not found or if it's the root itself.
bool removeNode(FNode root, FNode target) {
  for (final child in childrenOf(root)) {
    if (child.id == target.id) {
      final children = _mutableChildrenOf(root);
      children?.removeWhere((c) => c.id == target.id);
      return true;
    }
    if (removeNode(child, target)) return true;
  }
  return false;
}

/// Replaces [old] with [replacement] in the tree with root [root].
/// Returns false if [old] is not found.
bool replaceNode(FNode root, FNode old, FNode replacement) {
  final children = _mutableChildrenOf(root);
  if (children != null) {
    final idx = children.indexWhere((c) => c.id == old.id);
    if (idx >= 0) {
      children[idx] = replacement;
      return true;
    }
  }
  for (final child in childrenOf(root)) {
    if (replaceNode(child, old, replacement)) return true;
  }
  return false;
}

/// Moves [target] after [sibling] in the tree.
/// Equivalent to removeNode + insertAfter on the parent of [sibling].
bool moveAfter(FNode root, FNode target, FNode sibling) {
  final siblingParent = findParent(root, sibling);
  if (siblingParent == null) return false;
  if (!removeNode(root, target)) return false;
  return insertAfter(siblingParent, sibling, target);
}

// ═══════════════════════════════════════════════════════════════════════
// 3. INLINE CONTAINER — specific operations on inline fragments
// ═══════════════════════════════════════════════════════════════════════

/// Inserts [fragment] in [container] at position [index].
bool insertFragmentAt(InlineContainerNode container, Fragment fragment, int index) {
  final children = container.getChildren();
  if (index < 0 || index > children.length) return false;
  children.insert(index, fragment);
  return true;
}

/// Removes [fragment] from [container]. Returns false if not present.
bool removeFragment(InlineContainerNode container, Fragment fragment) {
  container.getChildren().removeWhere((c) => c.id == fragment.id);
  // getChildren() returns a list; removeWhere is void, check with indexOf first
  return true; // caller should verify with findNode if needed
}

/// Splits [fragment] at [offset] and inserts the right part in the container
/// immediately after [fragment]. Returns the right Fragment.
Fragment splitFragmentInContainer(
    InlineContainerNode container, Fragment fragment, int offset) {
  final (:left, :right) = FragmentOperations.splitFragment(fragment, offset);
  final children = container.getChildren();
  final idx = children.indexWhere((c) => c.id == left.id);
  if (idx >= 0) children.insert(idx + 1, right);
  return right;
}

/// Merges [fragment] with the Fragment immediately following in the container,
/// if it exists and if both have the same style.
/// Returns true if the merge occurred.
bool mergeWithNext(InlineContainerNode container, Fragment fragment) {
  final children = container.getChildren();
  final idx = children.indexWhere((c) => c.id == fragment.id);
  if (idx < 0 || idx >= children.length - 1) return false;
  final next = children[idx + 1];
  if (next is! Fragment || next is InlineContainerNode) return false;
  FragmentOperations.mergeFragments(fragment, next);
  children.removeAt(idx + 1);
  return true;
}

/// Removes empty Fragments from [container] (text == '').
/// Always leaves at least one Fragment to keep the container valid.
void pruneEmptyFragments(InlineContainerNode container) {
  final children = container.getChildren();
  if (children.length <= 1) return; // don't remove the last
  children.removeWhere((c) {
    if (c is FluentList || c is InlineContainerNode) return false;
    return c is Fragment && c.text.isEmpty;
  });
}

/// Cleans [node] from the document if it's an empty InlineContainerNode.
/// Climbs the tree and repeats if necessary (ex pruneEmpty).
void pruneEmptyContainers(FNode node, Root root) {
  if (node is! InlineContainerNode) return;
  final children = (node as InlineContainerNode).getChildren();
  if (children.isNotEmpty) return;
  final parent = findParent(root, node);
  if (parent == null) return;
  removeNode(root, node);
  if (parent is InlineContainerNode) pruneEmptyContainers(parent, root);
}

/// Empties a cell by removing all children except an empty Paragraph.
/// Maintains the table structure preserving at least one empty paragraph
/// to allow the cursor to be positioned in the cell.
void clearCellKeepingEmptyFragment(FluentCell cell, Root root) {
  // Remove all existing children
  final childrenToRemove = cell.children.toList();
  for (final child in childrenToRemove) {
    removeNode(root, child);
  }

  // Add an empty Paragraph to keep the cell "alive"
  final emptyParagraph = Paragraph();
  appendChild(cell, emptyParagraph);
}

/// Recalculates the indices of all lists in the document.
/// Updates indexList for each ListItem based on hierarchical position.
void recalculateListIndices(Root root) {
  void recalculateList(FluentList list, List<int> parentIndices) {
    for (var i = 0; i < list.items.length; i++) {
      final item = list.items[i];
      // Build the new indexList: parent + current position (1-based)
      final newIndexList = [...parentIndices, i + 1];
      item.indexList = newIndexList;

      // Check if the item has sublists in its children
      for (final child in item.children) {
        if (child is FluentList) {
          recalculateList(child, newIndexList);
        }
      }
    }
  }

  // Start from the root level
  for (final node in root.nodes) {
    if (node is FluentList) {
      recalculateList(node, []);
    }
  }
}

/// Merges consecutive lists with the same listType in the document.
/// This ensures that if two bullet lists are adjacent, they become one list.
/// This should be called after operations that create or modify lists.
void mergeConsecutiveLists(Root root) {
  void mergeInContainer(FNode container) {
    final children = childrenOf(container);
    final listsToMerge = <FluentList>[];

    // Find consecutive lists with the same type
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is FluentList) {
        // Only merge if it has the same type as the previous list
        if (listsToMerge.isEmpty || child.listType == listsToMerge.first.listType) {
          listsToMerge.add(child);
        } else {
          // Different type: merge accumulated lists and start new group
          if (listsToMerge.length > 1) {
            _mergeLists(root, listsToMerge);
          }
          listsToMerge.clear();
          listsToMerge.add(child);
        }
      } else {
        // Non-list node: merge any accumulated lists and reset
        if (listsToMerge.length > 1) {
          _mergeLists(root, listsToMerge);
        }
        listsToMerge.clear();
      }
    }

    // Merge any remaining lists at the end
    if (listsToMerge.length > 1) {
      _mergeLists(root, listsToMerge);
    }
  }

  // Process root level
  mergeInContainer(root);

  // Process nested lists (sublists in ListItem children)
  void processSublists(FNode node) {
    if (node is ListItem) {
      for (final child in node.children) {
        if (child is FluentList) {
          mergeInContainer(child);
          processSublists(child);
        }
      }
    } else {
      for (final child in childrenOf(node)) {
        processSublists(child);
      }
    }
  }

  processSublists(root);
}

/// Merges a list of consecutive FluentList nodes into the first one.
/// All items from subsequent lists are moved to the first list.
void _mergeLists(Root root, List<FluentList> lists) {
  if (lists.length < 2) return;

  final targetList = lists.first;

  // Move all items from subsequent lists to the target list
  for (var i = 1; i < lists.length; i++) {
    final sourceList = lists[i];
    for (final item in sourceList.items) {
      // Reset the indexList for numbered lists to ensure correct numbering
      // after merge. The indices will be recalculated by recalculateListIndices.
      item.indexList = [];
      appendChild(targetList, item);
    }
    // Remove the now-empty list
    removeNode(root, sourceList);
  }
}

/// Outdent of a ListItem at the first level: transforms into paragraph.
/// Removes the item from the list, takes the first Paragraph as content,
/// and promotes the other children (images, tables, sublists) to the parent level.
/// Returns the created Paragraph or null if the operation fails.
Paragraph? outdentListItemToParagraph(
  Root root,
  FluentList listParent,
  ListItem currentItem,
) {
  // Find the parent of the list (where to insert the item after outdent)
  final grandparent = findParent(root, listParent);
  if (grandparent == null) return null;

  // Snapshot of children before removing the item
  final itemChildren = currentItem.children.toList();

  // Extract the first Paragraph (which will become the new output paragraph)
  // and the other children that need to be promoted.
  Paragraph? firstParagraph;
  final otherChildren = <FNode>[];
  for (final c in itemChildren) {
    if (firstParagraph == null && c is Paragraph) {
      firstParagraph = c;
    } else {
      otherChildren.add(c);
    }
  }

  // Capture the items that come AFTER currentItem in the list:
  // they will go in a new separate list after the paragraph.
  final currentIndex = listParent.items.indexOf(currentItem);
  final itemsAfter = (currentIndex >= 0)
      ? listParent.items.sublist(currentIndex + 1).toList()
      : <ListItem>[];

  // Remove the current item from the list
  removeNode(root, currentItem);

  // Also remove the following items from the original list
  for (final item in itemsAfter) {
    removeNode(root, item);
  }

  // Detach the promoted children from the orphaned currentItem: so the nodes
  // exist ONLY in their new position in Root, avoiding double references
  // that confuse widget tree reconciliation and ParagraphRegistry during
  // cursor navigation.
  currentItem.children.clear();

  // If there's no Paragraph, create an empty one
  final newParagraph = firstParagraph ?? Paragraph();

  // Always insert the paragraph after the list (Google Docs behavior):
  // - If the list has other items, the paragraph goes after it
  // - If the list is empty (outdent of the last item), the paragraph goes after the empty list
  //   (the empty list will be removed after if necessary)
  insertAfter(grandparent, listParent, newParagraph);

  // Promote the other children of the ListItem (images, sublists, etc.)
  // immediately after the paragraph.
  var insertAfterNode = newParagraph as FNode;
  for (final child in otherChildren) {
    if (child is FluentList) {
      _promoteSublistRecursive(root, grandparent, insertAfterNode, child);
    } else {
      insertAfter(grandparent, insertAfterNode, child);
    }
    insertAfterNode = child;
  }

  // If there are following items, create a new separate list after the paragraph
  if (itemsAfter.isNotEmpty) {
    final newList = FluentList(listType: listParent.listType);
    for (final item in itemsAfter) {
      appendChild(newList, item);
    }
    insertAfter(grandparent, insertAfterNode, newList);
  }

  // If the original list remained empty, remove it to avoid empty orphan lists
  if (listParent.items.isEmpty) {
    removeNode(root, listParent);
  }

  // Merge consecutive lists with the same type
  mergeConsecutiveLists(root);

  // Recalculate the indices of all modified lists
  recalculateListIndices(root);

  return newParagraph;
}

/// Promotes a sublist and its possible nested sublists.
void _promoteSublistRecursive(
  FNode root,
  FNode grandparent,
  FNode insertAfterNode,
  FluentList sublist,
) {
  // Remove the sublist from its parent
  removeNode(root, sublist);

  // Insert the sublist after the specified node
  insertAfter(grandparent, insertAfterNode, sublist);

  // For each item in the sublist, handle its sublists
  for (final item in sublist.items) {
    // Find any nested sublists in the items
    final nestedSublists = item.children.whereType<FluentList>().toList();
    for (final nestedSublist in nestedSublists) {
      // Remove the nested sublist from the item
      removeNode(root, nestedSublist);
      // Insert it after the current sublist
      insertAfter(grandparent, sublist, nestedSublist);
    }
  }
}