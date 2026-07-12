import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
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
  final sel = resolveSelectionFromCursor(document);

  if (sel == null) return;

  final root = document.content;

  final cursorTarget = sel.isSingleNode
      ? _replaceSingleNode(sel, character, root)
      : _replaceMultiNode(sel, character, root);

  document.cursor.moveTo(
    cursorTarget.fragId,
    cursorTarget.offset,
  );

  document.selectionManager.collapse();

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

({String fragId, int offset}) _replaceSingleNode(
    ResolvedSelection sel, String character, Root root) {
  final baseFrag = sel.base.fragment;
  final extFrag  = sel.extent.fragment;
  final baseOff  = sel.base.offset.clamp(0, baseFrag.text.length);
  final extOff   = sel.extent.offset.clamp(0, extFrag.text.length);

  if (baseFrag.id == extFrag.id) {
    final newText = baseFrag.text.substring(0, baseOff) +
        character +
        baseFrag.text.substring(extOff);
    final newFrag = _setFragText(baseFrag, newText, root) ?? baseFrag;
    return (fragId: newFrag.id, offset: baseOff + character.length);
  }

  final newBaseText = baseFrag.text.substring(0, baseOff) + character;
  final newBaseFrag = _setFragText(baseFrag, newBaseText, root) ?? baseFrag;

  final newExtText = extFrag.text.substring(extOff);
  final newExtFrag = _setFragText(extFrag, newExtText, root);

  if (newExtFrag != null) {
    _removeFragmentsBetween(sel.base.container, newBaseFrag, newExtFrag, root);
  } else {
    _removeFragmentsAfter(sel.base.container, newBaseFrag, root);
  }

  if (newExtFrag != null && newExtFrag.text.isEmpty &&
      sel.base.container.getChildren().length > 1) {
    removeNode(root, newExtFrag);
  }

  return (fragId: newBaseFrag.id, offset: baseOff + character.length);
}

({String fragId, int offset}) _replaceMultiNode(
    ResolvedSelection sel, String character, Root root) {
  final baseNode = sel.nodes.first;
  final extNode  = sel.nodes.last;
  final baseFrag = sel.base.fragment;
  final extFrag  = sel.extent.fragment;
  final baseOff  = sel.base.offset.clamp(0, baseFrag.text.length);
  final extOff   = sel.extent.offset.clamp(0, extFrag.text.length);

  final newBaseText = baseFrag.text.substring(0, baseOff) + character;
  final newBaseFrag = _setFragText(baseFrag, newBaseText, root) ?? baseFrag;
  _removeFragmentsAfter(baseNode.container, newBaseFrag, root);

  for (int i = 1; i < sel.nodes.length - 1; i++) {
    final intermediateNode = sel.nodes[i].container as FNode;
    if (intermediateNode is FluentCell) {
      clearCellKeepingEmptyFragment(intermediateNode, root);
      continue;
    }
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
    removeNode(root, intermediateNode);
  }

  final newExtText = extFrag.text.substring(extOff);
  final newExtFrag = _setFragText(extFrag, newExtText, root);

  if (newExtFrag != null) {
    _removeFragmentsBefore(extNode.container, newExtFrag, root);
  }

  final toMove = extNode.container
      .getChildren()
      .where((c) => c is Fragment && c is! InlineContainerNode)
      .toList();

  for (final frag in toMove) {
    removeNode(root, frag);
    appendChild(baseNode.container as FNode, frag);
  }

  if (newExtFrag != null && newExtFrag.text.isEmpty && toMove.length > 1) {
    removeNode(root, newExtFrag);
  }

  if (extNode.container.getChildren()
      .every((c) => c is FluentList)) {
    removeNode(root, extNode.container as FNode);
  }

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

/// Recursively empties all cells of a table.
void _clearTableContents(FluentTable table, Root root) {
  for (final row in table.rows) {
    for (final cell in row.cells) {
      clearCellKeepingEmptyFragment(cell, root);
    }
  }
}

/// Removes from the tree all fragments of [container] (also nested in Links)
/// that come AFTER [start] and BEFORE [end] (start and end excluded).
void _removeFragmentsBetween(
  InlineContainerNode container,
  Fragment start,
  Fragment end,
  Root root,
) {
  final flat = flattenInlineChildren(container);
  final startIdx = flat.indexWhere((c) => c.id == start.id);
  final endIdx   = flat.indexWhere((c) => c.id == end.id);
  if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx + 1) return;

  final toRemove = flat.sublist(startIdx + 1, endIdx).toList();
  for (final node in toRemove) {
    removeNode(root, node);
  }
  _removeEmptyLinks(container, root);
}

/// Removes from the tree all children of [container] in the range
/// [startIdx, endIdx) (exclusive). Traverses Links transparently.
void _removeFragmentsRange(
  InlineContainerNode container,
  int startIdx,
  int endIdx,
  Root root,
) {
  final flat = flattenInlineChildren(container);
  if (startIdx < 0 || endIdx > flat.length || startIdx >= endIdx) return;

  final toRemove = flat.sublist(startIdx, endIdx).toList();
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
/// AFTER [pivot] (pivot excluded). Traverses Links transparently.
void _removeFragmentsAfter(
  InlineContainerNode container,
  Fragment pivot,
  Root root,
) {
  final flat = flattenInlineChildren(container);
  final pivotIdx = flat.indexWhere((c) => c.id == pivot.id);
  if (pivotIdx < 0) return;
  _removeFragmentsRange(container, pivotIdx + 1, flat.length, root);
}

/// Removes from the tree all children of [container] that come
/// BEFORE [pivot] (pivot excluded). Traverses Links transparently.
void _removeFragmentsBefore(
  InlineContainerNode container,
  Fragment pivot,
  Root root,
) {
  final flat = flattenInlineChildren(container);
  final pivotIdx = flat.indexWhere((c) => c.id == pivot.id);
  if (pivotIdx < 0) return;
  _removeFragmentsRange(container, 0, pivotIdx, root);
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
