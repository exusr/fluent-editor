// handle_replace_selection.dart
//
// Replaces the active selection with a single character.
// Uses resolveSelection to have real references to nodes, instead
// of working with FragmentRange/getFragmentsInRange.
//
// CASES HANDLED:
//   1. Same fragment: simple text replacement
//   2. Single node, different fragments: truncate edges, remove intermediate ones
//   3. Multi-node: truncate base and extent, remove intermediate nodes,
//      merge the surviving content of extent into the base node

import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Assigns text to a Fragment handling the special case FluentImage:
/// the image is atomic, so if [newText] is empty we remove it, if
/// it contains only the ZWS the image stays intact, otherwise we replace it
/// with a normal text Fragment.
/// Returns the actual Fragment after the operation (or null if removed).
Fragment? _setFragText(Fragment frag, String newText, Root root) {
  if (frag is HorizontalRule) {
    if (newText.isEmpty) {
      removeNode(root, frag);
      return null;
    }
    if (newText == Whitespaces.zws) {
      return frag; // HR survives intact
    }
    // HR is always block-level: replace with Paragraph wrapper
    final innerFrag = Fragment(newText);
    final wrapper = Paragraph()..fragments.add(innerFrag);
    replaceNode(root, frag, wrapper);
    return innerFrag;
  }

  if (frag is FluentImage) {
    if (newText.isEmpty) {
      removeNode(root, frag);
      return null;
    }
    if (newText == Whitespaces.zws) {
      return frag; // image survives intact
    }
    // If the image is inline (parent is Paragraph/Link), just a Fragment;
    // if it's block-level (parent is Root/ListItem/FluentCell), we need a
    // Paragraph wrapper otherwise the node is not renderable.
    final parent = findParent(root, frag);
    final isBlockLevel = parent is! Paragraph; // Link is Paragraph
    if (isBlockLevel) {
      final innerFrag = Fragment(newText);
      final wrapper = Paragraph()..fragments.add(innerFrag);
      replaceNode(root, frag, wrapper);
      return innerFrag;
    }
    final replacement = Fragment(newText);
    replaceNode(root, frag, replacement);
    return replacement;
  }
  frag.text = newText;
  return frag;
}

void executeHandleReplaceSelection(String character, FluentDocument document) {
  final sel = resolveSelection(
    document.content,
    document.cursor.anchorId,
    document.cursor.anchorOffset,
    document.cursor.focusId,
    document.cursor.focusOffset,
    cachedStops: document.caretStops,
    cachedLines: document.logicalLines,
  );

  if (sel == null) return;

  final root = document.content;

  final cursorTarget = sel.isSingleNode
      ? _replaceSingleNode(sel, character, root)
      : _replaceMultiNode(sel, character, root);

  // The cursor should be positioned immediately after the inserted character
  document.cursor.moveTo(
    cursorTarget.fragId,
    cursorTarget.offset,
  );

  // Collapse the global selection to remove the highlight
  document.selectionManager.collapse();

  // Notify comment system of the text mutation (single-fragment case for simplicity).
  if (sel.isSingleNode && sel.base.fragment.id == sel.extent.fragment.id) {
    final paragraphId = (sel.base.container as FNode).id;
    final globalOffset = document.getGlobalOffsetInParagraph(
      paragraphId,
      sel.base.fragment.id,
      sel.base.offset,
    );
    if (globalOffset != null) {
      final delta = character.length - (sel.extent.offset - sel.base.offset);
      document.notifyTextMutation(paragraphId, globalOffset, delta);
    }
  }

  recalculateListIndices(root);

  recalculateListIndicesFor(
    root,
    sel.nodes.map((n) => n.container as FNode).toSet(),
  );

  document.updateContent();
}

// ─── Case 1 / 2: selection inside a single node ─────────────────────

({String fragId, int offset}) _replaceSingleNode(
    ResolvedSelection sel, String character, Root root) {
  final baseFrag = sel.base.fragment;
  final extFrag  = sel.extent.fragment;
  // Clamp offsets to actual fragment text length to guard against stale
  // cursor state (e.g. on buffer-sync IME platforms where the fragment
  // text may have been modified without updating cursor offsets).
  final baseOff  = sel.base.offset.clamp(0, baseFrag.text.length);
  final extOff   = sel.extent.offset.clamp(0, extFrag.text.length);

  if (baseFrag.id == extFrag.id) {
    // ── Case 1: same fragment ─────────────────────────────────────
    final newText = baseFrag.text.substring(0, baseOff) +
        character +
        baseFrag.text.substring(extOff);
    final newFrag = _setFragText(baseFrag, newText, root) ?? baseFrag;
    return (fragId: newFrag.id, offset: baseOff + character.length);
  }

  // ── Case 2: different fragments in the same container ────────────────
  // 1. Truncate the base fragment: keep only [0..baseOff] + character
  final newBaseText = baseFrag.text.substring(0, baseOff) + character;
  final newBaseFrag = _setFragText(baseFrag, newBaseText, root) ?? baseFrag;

  // 2. Truncate the extent fragment: keep only [extOff..]
  final newExtText = extFrag.text.substring(extOff);
  final newExtFrag = _setFragText(extFrag, newExtText, root);

  // 3. Remove all fragments between base and extent (excluded)
  if (newExtFrag != null) {
    _removeFragmentsBetween(sel.base.container, newBaseFrag, newExtFrag, root);
  } else {
    _removeFragmentsAfter(sel.base.container, newBaseFrag, root);
  }

  // 4. If the extent fragment remained empty, remove it
  if (newExtFrag != null && newExtFrag.text.isEmpty &&
      sel.base.container.getChildren().length > 1) {
    removeNode(root, newExtFrag);
  }

  return (fragId: newBaseFrag.id, offset: baseOff + character.length);
}

// ─── Case 3: multi-node selection ─────────────────────────────────────

({String fragId, int offset}) _replaceMultiNode(
    ResolvedSelection sel, String character, Root root) {
  final baseNode = sel.nodes.first;
  final extNode  = sel.nodes.last;
  final baseFrag = sel.base.fragment;
  final extFrag  = sel.extent.fragment;
  // Clamp offsets to actual fragment text length to guard against stale
  // cursor state (e.g. on buffer-sync IME platforms where the fragment
  // text may have been modified without updating cursor offsets).
  final baseOff  = sel.base.offset.clamp(0, baseFrag.text.length);
  final extOff   = sel.extent.offset.clamp(0, extFrag.text.length);

  // 1. Truncate the base fragment and remove everything that comes after
  //    in the base node
  final newBaseText = baseFrag.text.substring(0, baseOff) + character;
  final newBaseFrag = _setFragText(baseFrag, newBaseText, root) ?? baseFrag;
  _removeFragmentsAfter(baseNode.container, newBaseFrag, root);

  // 2. Remove intermediate nodes (fully selected)
  //    but preserve tables by emptying their cells
  for (int i = 1; i < sel.nodes.length - 1; i++) {
    final intermediateNode = sel.nodes[i].container as FNode;
    // For cells: empty keeping an empty fragment
    if (intermediateNode is FluentCell) {
      clearCellKeepingEmptyFragment(intermediateNode, root);
      continue;
    }
    // For tables and rows: handle cells recursively
    if (intermediateNode is FluentTable) {
      for (final row in intermediateNode.rows) {
        for (final cell in row.cells) {
          clearCellKeepingEmptyFragment(cell, root);
        }
      }
      continue;
    }
    if (intermediateNode is FluentRow) {
      for (final cell in intermediateNode.cells) {
        clearCellKeepingEmptyFragment(cell, root);
      }
      continue;
    }
    // Other nodes: remove normally
    removeNode(root, intermediateNode);
  }

  // 3. Truncate the extent fragment: keep only [extOff..]
  final newExtText = extFrag.text.substring(extOff);
  final newExtFrag = _setFragText(extFrag, newExtText, root);

  // 4. Remove all fragments before extFrag in the extent node
  if (newExtFrag != null) {
    _removeFragmentsBefore(extNode.container, newExtFrag, root);
  }

  // 5. Move the surviving fragments of the extent node into the base node
  //    (only text Fragments, not FluentList or other containers)
  final toMove = extNode.container
      .getChildren()
      .where((c) => c is Fragment && c is! InlineContainerNode)
      .toList();

  for (final frag in toMove) {
    // Remove from extent node and add to base node
    removeNode(root, frag);
    appendChild(baseNode.container as FNode, frag);
  }

  // 6. Remove extFrag if it remained empty and is not the only one in the container
  if (newExtFrag != null && newExtFrag.text.isEmpty && toMove.length > 1) {
    removeNode(root, newExtFrag);
  }

  // 7. Remove the extent node (now emptied of its text fragments)
  //    Only if it has no remaining children (e.g., nested FluentLists that
  //    must survive)
  if (extNode.container.getChildren()
      .every((c) => c is FluentList)) {
    removeNode(root, extNode.container as FNode);
  }

  // 8. Hierarchical cleanup: remove empty ListItems and empty FluentLists that
  //    may remain after previous removals (e.g., when selecting
  //    from a main ListItem to a sub-ListItem).
  _cleanupEmptyListContainers(root);

  return (fragId: newBaseFrag.id, offset: baseOff + character.length);
}

/// Climbs up removing ListItem without Paragraph and FluentList without items.
void _cleanupEmptyListContainers(Root root) {
  bool removed;
  do {
    removed = false;
    final emptyItems = <ListItem>[];
    final emptyLists = <FluentList>[];
    walkTree(root, (node, _) {
      if (node is ListItem && !node.children.any((c) => c is Paragraph)) {
        emptyItems.add(node);
      } else if (node is FluentList && node.items.isEmpty) {
        emptyLists.add(node);
      }
      return true;
    });
    for (final n in emptyItems) {
      if (removeNode(root, n)) removed = true;
    }
    for (final n in emptyLists) {
      if (removeNode(root, n)) removed = true;
    }
  } while (removed);
}

// ─── Helpers ──────────────────────────────────────────────────────────

/// Recursively empties all cells of a table.
void _clearTableContents(FluentTable table, Root root) {
  for (final row in table.rows) {
    for (final cell in row.cells) {
      clearCellKeepingEmptyFragment(cell, root);
    }
  }
}

/// Returns the "flat" list of children of [container] in reading order,
/// expanding Links (transparent) into their fragments.
/// Necessary because start/pivot/end can be fragments nested in a
/// Link, not direct children of the container.
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

/// Removes from the tree all fragments of [container] (also nested in Links)
/// that come AFTER [start] and BEFORE [end] (start and end excluded).
void _removeFragmentsBetween(
  InlineContainerNode container,
  Fragment start,
  Fragment end,
  Root root,
) {
  final flat = _flattenInlineChildren(container);
  final startIdx = flat.indexWhere((c) => c.id == start.id);
  final endIdx   = flat.indexWhere((c) => c.id == end.id);
  if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx + 1) return;

  final toRemove = flat.sublist(startIdx + 1, endIdx).toList();
  for (final node in toRemove) {
    removeNode(root, node);
  }
  _removeEmptyLinks(container, root);
}

/// Removes from the tree all children of [container] that come
/// AFTER [pivot] (pivot excluded). Traverses Links transparently.
void _removeFragmentsAfter(
  InlineContainerNode container,
  Fragment pivot,
  Root root,
) {
  final flat = _flattenInlineChildren(container);
  final pivotIdx = flat.indexWhere((c) => c.id == pivot.id);
  if (pivotIdx < 0) return;

  final toRemove = flat.sublist(pivotIdx + 1).toList();
  for (final node in toRemove) {
    if (node is FluentList) continue;
    if (node is FluentTable) {
      _clearTableContents(node, root);
      continue;
    }
    if (node is FluentRow) continue;
    if (node is FluentCell) {
      clearCellKeepingEmptyFragment(node, root);
      continue;
    }
    removeNode(root, node);
  }
  _removeEmptyLinks(container, root);
}

/// Removes from the tree all children of [container] that come
/// BEFORE [pivot] (pivot excluded). Traverses Links transparently.
void _removeFragmentsBefore(
  InlineContainerNode container,
  Fragment pivot,
  Root root,
) {
  final flat = _flattenInlineChildren(container);
  final pivotIdx = flat.indexWhere((c) => c.id == pivot.id);
  if (pivotIdx < 0) return;

  final toRemove = flat.sublist(0, pivotIdx).toList();
  for (final node in toRemove) {
    if (node is FluentList) continue;
    if (node is FluentTable) {
      _clearTableContents(node, root);
      continue;
    }
    if (node is FluentRow) continue;
    if (node is FluentCell) {
      clearCellKeepingEmptyFragment(node, root);
      continue;
    }
    removeNode(root, node);
  }
  _removeEmptyLinks(container, root);
}

/// Removes Links that remained without any child fragment.
void _removeEmptyLinks(InlineContainerNode container, Root root) {
  final emptyLinks = container
      .getChildren()
      .whereType<Link>()
      .where((l) => l.getChildren().isEmpty)
      .toList();
  for (final link in emptyLinks) {
    removeNode(root, link);
  }
}
