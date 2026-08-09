import 'package:fluent_editor/core/constants.dart';
import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
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

  if (!cursor.isCollapsed && nodeType == 'list') {
    final sel = resolveSelectionFromCursor(document);
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
        executeHandleReplaceSelection('', document);
        final list = FluentList(
          listType: options['listType'] as String? ?? 'bullet',
        );
        list.items.addAll(items);
        _insertBlockNode(root, document.cursor, list, document);
        return;
      }
    }
  }

  if (!cursor.isCollapsed) {
    executeHandleReplaceSelection('', document);
  }

  final newNode = makeNode(nodeType, options);

  if (newNode is Link) {
    _insertLinkInline(root, cursor, newNode, document);
    return;
  }

  if (newNode is FluentImage) {
    _insertImage(root, cursor, newNode, document);
    return;
  }

  _insertBlockNode(root, cursor, newNode, document);
}

/// Inserts a Link inline at the cursor, splitting the fragment.
void _insertLinkInline(
  Root root,
  Cursor cursor,
  Link newLink,
  FluentDocument document,
) {
  final currentFrag = document.nodeById(cursor.anchorId) as Fragment?;
  if (currentFrag == null) {
    _insertBlockNode(root, cursor, newLink, document);
    return;
  }

  final container = document.findLogicalContainerCached(cursor.anchorId);
  if (container == null) {
    _insertBlockNode(root, cursor, newLink, document);
    return;
  }

  final offset = cursor.anchorOffset;
  final text = currentFrag.text;

  final beforeText = text.substring(0, offset);
  final afterText = text.substring(offset);

  currentFrag.text = beforeText;

  insertAfter(container as FNode, currentFrag, newLink);

  if (afterText.isNotEmpty) {
    final afterFrag = Fragment(afterText)
      ..styles = List.from(currentFrag.styles ?? [])
      ..fontFamily = currentFrag.fontFamily
      ..fontSize = currentFrag.fontSize;
    insertAfter(container as FNode, newLink, afterFrag);
  }

  _moveCursorToNodeStart(cursor, newLink);

  recalculateAndUpdate(document);
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
  final container =
      document.findLogicalContainerCached(cursor.anchorId) as FNode?;
  if (container is Paragraph) {
    final containerParent = findParentCached(document, container);
    if (containerParent is Root) {
      final atEnd = _isCursorAtEndOfContainer(
        root,
        cursor,
        container,
        cachedStops: document.caretStops,
        document: document,
      );
      final atStart =
          cursor.anchorOffset == 0 &&
          container.getChildren().isNotEmpty &&
          container.getChildren().first.id == cursor.anchorId;
      if (atStart) {
        insertBefore(root, container, newImage);
        recalculateAndUpdate(document);
        return;
      }
      if (atEnd) {
        insertAfter(root, container, newImage);
        final newParagraph = Paragraph();
        insertAfter(root, newImage, newParagraph);
        final firstFrag = newParagraph.getChildren().first;
        cursor.moveTo(firstFrag.id, 0);
        recalculateAndUpdate(document);
        return;
      }
    }
  }

  final currentFrag = document.nodeById(cursor.anchorId) as Fragment?;
  if (currentFrag == null) return;
  final parent = findParentCached(document, currentFrag);
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
  }
  cursor.moveTo(newImage.id, 1);
  final containerId = document.findLogicalContainerId(newImage.id) ?? parent.id;
  document.selectionManager.startSelection(containerId, newImage.id, 1);

  recalculateAndUpdate(document);
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
  if (newNode is FluentTable) {
    final container =
        document.findLogicalContainerCached(cursor.anchorId) as FNode?;
    if (container != null) {
      final listItem = findAncestorCached<ListItem>(document, container);
      if (listItem != null) return;
    }
  }

  FNode? container =
      document.findLogicalContainerCached(cursor.anchorId) as FNode?;
  if (container == null) {
    appendChild(root, newNode);
    _moveCursorToNodeStart(cursor, newNode);
    recalculateAndUpdate(document);
    return;
  }

  final cell = findAncestorCached<FluentCell>(document, container);
  if (cell != null) {
    if (newNode is FluentTable) return;
    appendChild(cell, newNode);
    _moveCursorToNodeStart(cursor, newNode);
    recalculateAndUpdate(document);
    return;
  }

  final listItem = findAncestorCached<ListItem>(document, container);
  if (listItem != null) {
    if (newNode is FluentTable) return;
    appendChild(listItem, newNode);
    _moveCursorToNodeStart(cursor, newNode);
    recalculateAndUpdate(document);
    return;
  }

  if (container is Link) {
    FNode? current = container;
    FNode? parent = findParentCached(document, current);
    while (parent != null && parent is! Paragraph && parent is! ListItem) {
      current = parent;
      parent = findParentCached(document, current);
    }
    if (parent != null) {
      insertAfter(parent, current as FNode, newNode);
      _moveCursorToNodeStart(cursor, newNode);
      recalculateAndUpdate(document);
      return;
    }
  }

  final containerParent = findParentCached(document, container);
  if (container is Paragraph && containerParent is Root) {
    final atEnd = _isCursorAtEndOfContainer(
      root,
      cursor,
      container,
      cachedStops: document.caretStops,
      document: document,
    );
    final atStart =
        cursor.anchorOffset == 0 &&
        container.getChildren().isNotEmpty &&
        container.getChildren().first.id == cursor.anchorId;
    if (atEnd) {
      insertAfter(root, container, newNode);
      _moveCursorToNodeStart(cursor, newNode);
      recalculateAndUpdate(document);
      return;
    }
    if (atStart) {
      insertBefore(root, container, newNode);
      _moveCursorToNodeStart(cursor, newNode);
      recalculateAndUpdate(document);
      return;
    }
    _splitParagraphAtCursor(root, cursor, container, newNode, document);
    return;
  }

  FNode? parent = findParentCached(document, container);
  while (parent != null && parent is! Root && parent is! FluentList) {
    container = parent;
    parent = findParentCached(document, container);
  }

  if (parent == null) {
    appendChild(root, newNode);
  } else {
    insertAfter(parent, container as FNode, newNode);
  }

  _moveCursorToNodeStart(cursor, newNode);

  recalculateAndUpdate(document);
}

/// Verifies if the cursor is at the last stop of [container].
/// If [cachedStops] is provided (e.g. document.caretStops), it is used
/// directly instead of rebuilding the entire stop rail with buildAllStops.
bool _isCursorAtEndOfContainer(
  Root root,
  Cursor cursor,
  InlineContainerNode container, {
  List<CaretStop>? cachedStops,
  FluentDocument? document,
}) {
  final stops = cachedStops ?? buildAllStops(root);
  final containerId = (container as FNode).id;
  final containerStops = stops.where((s) {
    final c =
        document?.findLogicalContainerId(s.fragmentId) ??
        (findLogicalContainer(root, s.fragmentId) as FNode?)?.id;
    return c != null && c == containerId;
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

  frag.text = beforeText;

  final children = paragraph.getChildren();
  final fragIdx = children.indexWhere((c) => c.id == frag.id);
  final toMove = fragIdx >= 0
      ? children.sublist(fragIdx + 1).toList()
      : <FNode>[];

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

  insertAfter(root, paragraph, newNode);
  insertAfter(root, newNode, afterParagraph);

  _moveCursorToNodeStart(cursor, newNode);
  recalculateAndUpdate(document);
}

/// Moves the cursor to the start of a newly created node.
void _moveCursorToNodeStart(Cursor cursor, FNode node) {
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
  cursor.moveTo(node.id, 0);
}

/// Extracts the selected plain text from a [SelectedNode].
/// Links are flattened so their inner Fragments are traversed.
String _extractSelectedText(Root root, SelectedNode selectedNode) {
  final container = selectedNode.container;

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
