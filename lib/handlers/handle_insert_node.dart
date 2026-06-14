import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

/// Inserts a new node at the cursor.
///
/// - If there's a selection: it's removed first.
/// - Link (inline): inserted at the cursor, splitting the fragment.
/// - Other nodes (block): inserted after the current container.
void handleInsertNodeExceution(
  String nodeType,
  FluentDocument document,
  Map<String, dynamic> options,
) {
  final root = document.content;
  final cursor = document.cursor;

  // If there's a selection and we're inserting a list, convert the
  // selected text into list items.
  if (!cursor.isCollapsed && nodeType == 'list') {
    final sel = resolveSelection(
      root,
      cursor.anchorId,
      cursor.anchorOffset,
      cursor.focusId,
      cursor.focusOffset,
      cachedStops: document.caretStops,
      cachedLines: document.logicalLines,
    );
    if (sel != null && sel.nodes.isNotEmpty) {
      final items = <ListItem>[];
      for (final node in sel.nodes) {
        final text = _extractSelectedText(root, node);
        if (text.isNotEmpty && text != Whitespaces.zws) {
          final paragraph = Paragraph(text: text);
          final firstFrag = paragraph.fragments.first as Fragment;
          final sourceFrag = _findFirstFragmentInSelection(root, node);
          if (sourceFrag != null) {
            firstFrag.styles = List<String>.from(sourceFrag.styles ?? []);
            firstFrag.fontFamily = sourceFrag.fontFamily;
            firstFrag.fontSize = sourceFrag.fontSize;
            firstFrag.color = sourceFrag.color;
            firstFrag.highlightColor = sourceFrag.highlightColor;
          }
          final item = ListItem(
            bulletType: options['listType'] as String? ?? 'bullet',
            indexList: [1],
            children: [paragraph],
          );
          items.add(item);
        }
      }
      if (items.isNotEmpty) {
        // Remove the selected text (collapses cursor).
        executeHandleReplaceSelection('', document);
        // Build the list with the extracted text.
        final list = FluentList(
          listType: options['listType'] as String? ?? 'bullet',
        );
        list.items.addAll(items);
        _insertBlockNode(root, document.cursor, list, document);
        return;
      }
    }
  }

  // If there's a selection, remove it and collapse the cursor.
  if (!cursor.isCollapsed) {
    executeHandleReplaceSelection('', document);
  }

  // Create the new node
  final newNode = makeNode(nodeType, options);

  // Link is inline: insert it inside the container at the cursor
  if (newNode is Link) {
    _insertLinkInline(root, cursor, newNode, document);
    return;
  }

  // Image: inline by default, block only when the cursor is
  // at the beginning or end of a root-level Paragraph.
  if (newNode is FluentImage) {
    _insertImage(root, cursor, newNode, document);
    return;
  }

  // Other nodes are block: insert them after the current container
  _insertBlockNode(root, cursor, newNode, document);
}

/// Inserts a Link inline at the cursor, splitting the fragment.
void _insertLinkInline(
  Root root,
  Cursor cursor,
  Link newLink,
  FluentDocument document,
) {
  // Find the fragment where the cursor is positioned
  final currentFrag = findNode(root, (n) => n.id == cursor.anchorId) as Fragment?;
  if (currentFrag == null) {
    // We're not in a fragment, fallback to block insertion
    _insertBlockNode(root, cursor, newLink, document);
    return;
  }

  // Find the logical container (Paragraph, ListItem, FluentCell, etc.)
  final container = findLogicalContainer(root, cursor.anchorId);
  if (container == null) {
    _insertBlockNode(root, cursor, newLink, document);
    return;
  }

  final offset = cursor.anchorOffset;
  final text = currentFrag.text;

  // Split the text at the cursor
  final beforeText = text.substring(0, offset);
  final afterText = text.substring(offset);

  // Update the current fragment with the text before
  currentFrag.text = beforeText;

  // Insert the Link after the current fragment
  insertAfter(container as FNode, currentFrag, newLink);

  // If there's text after, create a new fragment with the same style
  if (afterText.isNotEmpty) {
    final afterFrag = Fragment(afterText)
      ..styles = List.from(currentFrag.styles ?? [])
      ..fontFamily = currentFrag.fontFamily
      ..fontSize = currentFrag.fontSize;
    insertAfter(container as FNode, newLink, afterFrag);
  }

  // Position the cursor at the start of the Link
  _moveCursorToNodeStart(cursor, newLink);

  // Recalculate the list indices if we inserted after a list item
  recalculateListIndices(root);

  document.updateContent();
}

/// Inserts an image.
///
/// - If cursor is at the start of a root-level Paragraph → block before.
/// - If cursor is at the end of a root-level Paragraph → block after.
/// - Otherwise → inline (split the current fragment).
void _insertImage(
  Root root,
  Cursor cursor,
  FluentImage newImage,
  FluentDocument document,
) {
  final container = findLogicalContainer(root, cursor.anchorId) as FNode?;
  if (container is Paragraph) {
    final containerParent = findParent(root, container);
    if (containerParent is Root) {
      final atEnd = _isCursorAtEndOfContainer(
        root, cursor, container,
        cachedStops: document.caretStops,
      );
      final atStart = cursor.anchorOffset == 0 &&
          container.getChildren().isNotEmpty &&
          container.getChildren().first.id == cursor.anchorId;
      if (atStart) {
        insertBefore(root, container, newImage);
        // Cursor stays in the existing paragraph
        recalculateListIndices(root);
        document.updateContent();
        return;
      }
      if (atEnd) {
        insertAfter(root, container, newImage);
        // Create an empty paragraph after the image for the cursor
        final newParagraph = Paragraph();
        insertAfter(root, newImage, newParagraph);
        final firstFrag = newParagraph.getChildren().first;
        cursor.moveTo(firstFrag.id, 0);
        recalculateListIndices(root);
        document.updateContent();
        return;
      }
    }
  }

  // Inline: find the current fragment and split
  final currentFrag = document.nodeById(cursor.anchorId) as Fragment?;
  if (currentFrag == null) return;
  final parent = findParent(root, currentFrag);
  if (parent == null) return;

  final offset = cursor.anchorOffset;
  final beforeText = currentFrag.text.substring(0, offset);
  final afterText = currentFrag.text.substring(offset);

  currentFrag.text = beforeText;
  insertAfter(parent, currentFrag, newImage);
  if (afterText.isNotEmpty) {
    final afterFrag = Fragment(afterText)
      ..styles = List.from(currentFrag.styles ?? [])
      ..fontFamily = currentFrag.fontFamily
      ..fontSize = currentFrag.fontSize;
    insertAfter(parent, newImage, afterFrag);
    cursor.moveTo(afterFrag.id, 0);
  } else {
    // If there's no text after, stay in the fragment before the image
    cursor.moveTo(currentFrag.id, beforeText.length);
  }

  recalculateListIndices(root);
  document.updateContent();
}

/// Inserts a block node after the current container.
///
/// If the container is a FluentCell, inserts the node as a child of the cell.
/// If the cursor is in a Link, exits the Link and inserts after the parent Paragraph.
/// Otherwise, inserts after the container in the appropriate parent.
void _insertBlockNode(
  Root root,
  Cursor cursor,
  FNode newNode,
  FluentDocument document,
) {
  // Tables are not allowed in lists: check if cursor is in a list
  if (newNode is FluentTable) {
    final container = findLogicalContainer(root, cursor.anchorId) as FNode?;
    if (container != null) {
      final listItem = _findEnclosingListItem(root, container);
      if (listItem != null) return;
    }
  }

  // Find the logical container where the cursor is positioned
  FNode? container = findLogicalContainer(root, cursor.anchorId) as FNode?;
  if (container == null) {
    // Fallback: add to root
    appendChild(root, newNode);
    _moveCursorToNodeStart(cursor, newNode);
    recalculateListIndices(root);
    document.updateContent();
    return;
  }

  // If we're in a cell, add the node as a child of the cell.
  // Nested tables are not allowed: ignore the command.
  final cell = _findEnclosingCell(root, container);
  if (cell != null) {
    if (newNode is FluentTable) return;
    appendChild(cell, newNode);
    _moveCursorToNodeStart(cursor, newNode);
    recalculateListIndices(root);
    document.updateContent();
    return;
  }

  // If we're in a ListItem, add the node as a child of the ListItem
  // Tables in ListItems are not allowed: ignore the command.
  final listItem = _findEnclosingListItem(root, container);
  if (listItem != null) {
    if (newNode is FluentTable) return;
    appendChild(listItem, newNode);
    _moveCursorToNodeStart(cursor, newNode);
    recalculateListIndices(root);
    document.updateContent();
    return;
  }

  // If we're in a Link, we must exit the Link and insert in the parent Paragraph
  if (container is Link) {
    // Find the Paragraph that contains this Link
    FNode? current = container;
    FNode? parent = findParent(root, current);
    while (parent != null && parent is! Paragraph && parent is! ListItem) {
      current = parent;
      parent = findParent(root, current);
    }
    if (parent != null) {
      insertAfter(parent, current as FNode, newNode);
      _moveCursorToNodeStart(cursor, newNode);
      recalculateListIndices(root);
      document.updateContent();
      return;
    }
  }

  // --- Special case: cursor at end/start of a root-level Paragraph ---
  // If the container is a Paragraph whose parent is Root, and the cursor is
  // at the beginning or end, insert directly in Root without splitting.
  final containerParent = findParent(root, container);
  if (container is Paragraph && containerParent is Root) {
    final atEnd = _isCursorAtEndOfContainer(
      root, cursor, container,
      cachedStops: document.caretStops,
    );
    final atStart = cursor.anchorOffset == 0 &&
        container.getChildren().isNotEmpty &&
        container.getChildren().first.id == cursor.anchorId;
    if (atEnd) {
      insertAfter(root, container, newNode);
      _moveCursorToNodeStart(cursor, newNode);
      recalculateListIndices(root);
      document.updateContent();
      return;
    }
    if (atStart) {
      insertBefore(root, container, newNode);
      _moveCursorToNodeStart(cursor, newNode);
      recalculateListIndices(root);
      document.updateContent();
      return;
    }
    // In the middle: split the Paragraph
    _splitParagraphAtCursor(root, cursor, container, newNode, document);
    return;
  }

  // Climb the hierarchy until finding a node whose parent can
  // contain block nodes (e.g., Root, or a ListItem that can have sublists)
  FNode? parent = findParent(root, container);
  while (parent != null && parent is! Root && parent is! FluentList) {
    container = parent;
    parent = findParent(root, container);
  }

  // Insert the new node
  if (parent == null) {
    appendChild(root, newNode);
  } else {
    insertAfter(parent, container as FNode, newNode);
  }

  // Position the cursor at the start of the new node
  _moveCursorToNodeStart(cursor, newNode);

  // Recalculate the list indices if we inserted after a list item
  recalculateListIndices(root);

  document.updateContent();
}

/// Finds the FluentCell that contains the given node, if it exists.
FluentCell? _findEnclosingCell(Root root, FNode node) {
  FNode? current = node;
  while (current != null) {
    if (current is FluentCell) return current;
    current = findParent(root, current);
  }
  return null;
}

/// Finds the ListItem that contains the given node, if it exists.
ListItem? _findEnclosingListItem(Root root, FNode node) {
  FNode? current = node;
  while (current != null) {
    if (current is ListItem) return current;
    current = findParent(root, current);
  }
  return null;
}

/// Verifies if the cursor is at the last stop of [container].
/// If [cachedStops] is provided (e.g. document.caretStops), it is used
/// directly instead of rebuilding the entire stop rail with buildAllStops.
bool _isCursorAtEndOfContainer(
  Root root,
  Cursor cursor,
  InlineContainerNode container, {
  List<CaretStop>? cachedStops,
}) {
  final stops = cachedStops ?? buildAllStops(root);
  final containerId = (container as FNode).id;
  final containerStops = stops.where((s) {
    final c = findLogicalContainer(root, s.fragmentId);
    return c != null && (c as FNode).id == containerId;
  }).toList();
  if (containerStops.isEmpty) return false;
  final lastStop = containerStops.last;
  return cursor.anchorId == lastStop.fragmentId &&
      cursor.anchorOffset == lastStop.offset;
}

/// Splits a Paragraph at the cursor: the text before stays in the original
/// paragraph, the text after (and any subsequent fragments) goes in a new
/// Paragraph. The [newNode] is inserted between the two.
void _splitParagraphAtCursor(
  Root root,
  Cursor cursor,
  Paragraph paragraph,
  FNode newNode,
  FluentDocument document,
) {
  final fragNode = document.nodeById(cursor.anchorId);
  final frag = fragNode is Fragment ? fragNode : null;
  if (frag == null) return;

  final offset = cursor.anchorOffset;
  final beforeText = frag.text.substring(0, offset);
  final afterText = frag.text.substring(offset);

  // Update the current fragment with the text before
  frag.text = beforeText;

  // Collect the subsequent fragments to move to the new paragraph
  final children = paragraph.getChildren();
  final fragIdx = children.indexWhere((c) => c.id == frag.id);
  final toMove = fragIdx >= 0 ? children.sublist(fragIdx + 1).toList() : <FNode>[];

  // Create the paragraph after, inheriting the style of the original fragment
  final afterParagraph = Paragraph();
  final firstAfterFrag = Fragment(afterText.isNotEmpty ? afterText : '')
    ..styles = List.from(frag.styles ?? [])
    ..fontFamily = frag.fontFamily
    ..fontSize = frag.fontSize;
  afterParagraph.fragments.add(firstAfterFrag);
  for (final moved in toMove) {
    removeNode(root, moved);
    appendChild(afterParagraph, moved);
  }

  // Insert newNode and afterParagraph in root after the original paragraph
  insertAfter(root, paragraph, newNode);
  insertAfter(root, newNode, afterParagraph);

  _moveCursorToNodeStart(cursor, newNode);
  recalculateListIndices(root);
  document.updateContent();
}

/// Moves the cursor to the start of a newly created node.
void _moveCursorToNodeStart(Cursor cursor, FNode node) {
  // For inline containers, descend recursively until we find the
  // first Fragment (e.g. FluentList -> ListItem -> Paragraph -> Fragment).
  if (node is InlineContainerNode) {
    final children = childrenOf(node);
    if (children.isNotEmpty) {
      final first = children.first;
      if (first is Fragment) {
        cursor.moveTo(first.id, 0);
        return;
      }
      _moveCursorToNodeStart(cursor, first);
      return;
    }
  }
  // Fallback: position on the node itself with offset 0
  cursor.moveTo(node.id, 0);
}

/// Extracts the selected plain text from a [SelectedNode].
/// Links are flattened so their inner Fragments are traversed.
String _extractSelectedText(Root root, SelectedNode selectedNode) {
  final container = selectedNode.container;

  // Build a flat list of Fragments inside the container (expanding Links)
  final flatFrags = <Fragment>[];
  for (final child in container.getChildren()) {
    if (child is Link) {
      for (final inner in child.getChildren()) {
        if (inner is Fragment) flatFrags.add(inner);
      }
    } else if (child is Fragment) {
      flatFrags.add(child);
    }
  }

  final startIdx = flatFrags.indexWhere(
    (f) => f.id == selectedNode.startFragment.id,
  );
  final endIdx = flatFrags.indexWhere(
    (f) => f.id == selectedNode.endFragment.id,
  );
  if (startIdx < 0 || endIdx < 0) return '';

  final buffer = StringBuffer();
  for (var i = startIdx; i <= endIdx; i++) {
    final frag = flatFrags[i];
    if (i == startIdx && i == endIdx) {
      buffer.write(
        frag.text.substring(selectedNode.startOffset, selectedNode.endOffset),
      );
    } else if (i == startIdx) {
      buffer.write(frag.text.substring(selectedNode.startOffset));
    } else if (i == endIdx) {
      buffer.write(frag.text.substring(0, selectedNode.endOffset));
    } else {
      buffer.write(frag.text);
    }
  }
  return buffer.toString();
}

/// Returns the first Fragment that matches the selection start inside the
/// container, useful for copying styles to the newly created list item.
Fragment? _findFirstFragmentInSelection(Root root, SelectedNode selectedNode) {
  final container = selectedNode.container;
  for (final child in container.getChildren()) {
    if (child is Link) {
      for (final inner in child.getChildren()) {
        if (inner is Fragment && inner.id == selectedNode.startFragment.id) {
          return inner;
        }
      }
    } else if (child is Fragment && child.id == selectedNode.startFragment.id) {
      return child;
    }
  }
  return null;
}
