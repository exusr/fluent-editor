import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/handlers/handle_tab.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';

/// Handles the ENTER key.
///
/// - Paragraphs: creates a new paragraph below or splits content if in the middle
/// - Cells: creates a new fragment with line break or new row if at the end
/// - Lists: creates a new list item
bool executeHandleEnter(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;

  if (!cursor.isCollapsed) {
    executeHandleReplaceSelection('', document);
  }

  final container = findLogicalContainer(root, cursor.anchorId);
  if (container == null) return false;

  if (container is Link) {
    return _handleLinkEnter(document, container);
  }

  if (container is Paragraph) {
    final ancestorItem = findAncestorListItem(root, container);
    if (ancestorItem != null) {
      return _handleListEnter(document, ancestorItem, container);
    }
    final ancestorCell = findAncestorCell(root, container);
    if (ancestorCell != null) {
      return _handleCellEnter(document, ancestorCell);
    }
  }

  return _handleParagraphEnter(document, container);
}

/// Handles ENTER inside a ListItem (structure: children: [Paragraph, ...]).
///
/// Splits the current Paragraph at cursor. The content after the cursor,
/// plus all subsequent children of the ListItem (images, sublists, etc.),
/// are moved to a new ListItem.
bool _handleListEnter(
  FluentDocument document,
  ListItem currentItem,
  Paragraph currentParagraph,
) {
  final root = document.content;

  final isItemEmpty = currentItem.children.length == 1 &&
      currentParagraph.text.isEmpty;
  if (isItemEmpty) {
    return executeHandleOutdentItem(document, currentItem);
  }

  final cursor = document.cursor;

  final listParent = findParent(root, currentItem);
  if (listParent is! FluentList) return false;

  final newItem = ListItem(
    bulletType: currentItem.bulletType,
    indexList: [],
    children: [],
  );

  final currentStyle = currentParagraph.getStyle();
  final newStyleName = currentStyle.name.startsWith('heading')
      ? 'normal'
      : currentParagraph.styleName;

  final newParagraph = Paragraph(
    textAlign: currentParagraph.textAlign,
    indent: currentParagraph.indent,
    styleName: newStyleName,
  );
  final defaultFrag = newParagraph.fragments.first;
  removeNode(newParagraph, defaultFrag);

  final currentFrag = findNode(root, (n) => n.id == cursor.anchorId) as Fragment?;

  Fragment? cursorTarget;

  if (currentFrag != null) {
    final text = currentFrag.text;
    final offset = cursor.anchorOffset.clamp(0, text.length);
    final beforeText = text.substring(0, offset);
    final afterText = text.substring(offset);

    currentFrag.text = beforeText;

    final afterFrag = FragmentOperations.cloneFragment(currentFrag, text: afterText);
    appendChild(newParagraph, afterFrag);
    cursorTarget = afterFrag;

    final pFrags = currentParagraph.fragments.toList();
    final idx = pFrags.indexOf(currentFrag);
    if (idx >= 0) {
      for (var i = idx + 1; i < pFrags.length; i++) {
        final f = pFrags[i];
        removeNode(root, f);
        appendChild(newParagraph, f);
      }
    }
  } else {
    final emptyFrag = FragmentOperations.createFragmentWithPendingStyles(document, '');
    appendChild(newParagraph, emptyFrag);
    cursorTarget = emptyFrag;
  }

  appendChild(newItem, newParagraph);

  final itemChildren = currentItem.children.toList();
  final pIdx = itemChildren.indexOf(currentParagraph);
  if (pIdx >= 0) {
    for (var i = pIdx + 1; i < itemChildren.length; i++) {
      final c = itemChildren[i];
      removeNode(root, c);
      appendChild(newItem, c);
    }
  }

  insertAfter(listParent, currentItem, newItem);

  cursor.moveTo(cursorTarget.id, 0);

  recalculateListIndices(root);
  document.updateContent();
  return true;
}

/// Handles ENTER inside a cell.
/// If cursor is at the end of the cell, moves to the next cell (like TAB).
/// Otherwise, splits the content.
bool _handleCellEnter(FluentDocument document, FluentCell currentCell) {
  final root = document.content;
  final cursor = document.cursor;

  final currentFrag = findNode(root, (n) => n.id == cursor.anchorId) as Fragment?;
  if (currentFrag == null) {
    return _insertEmptyFragmentInCell(document, currentCell);
  }

  final text = currentFrag.text;
  final offset = cursor.anchorOffset;

  currentFrag.text = '${text.substring(0, offset)}\n${text.substring(offset)}';

  document.updateContent();

  cursor.moveTo(currentFrag.id, offset + 1);

  return true;
}

/// Inserts an empty fragment in a cell.
bool _insertEmptyFragmentInCell(
  FluentDocument document,
  FluentCell cell, {
  Fragment? before,
}) {
  final cursor = document.cursor;
  final newFrag = FragmentOperations.createFragmentWithPendingStyles(document, '');

  if (before != null) {
    insertBefore(cell, before, newFrag);
  } else {
    appendChild(cell, newFrag);
  }

  cursor.moveTo(newFrag.id, 0);
  document.updateContent();
  return true;
}

/// Handles ENTER inside a Link.
/// If the Link is inside a Paragraph, delegates the split to the parent paragraph.
/// Otherwise treats the Link as a top-level container.
bool _handleLinkEnter(FluentDocument document, Link currentLink) {
  final root = document.content;
  final linkParent = findParent(root, currentLink);
  if (linkParent == null) return false;

  if (linkParent is Paragraph && linkParent is! Link) {
    return _splitInlineContainer(document, linkParent);
  }

  return _splitInlineContainer(document, currentLink);
}

/// Handles ENTER in a paragraph (or other inline container).
bool _handleParagraphEnter(
  FluentDocument document,
  InlineContainerNode container,
) {
  return _splitInlineContainer(document, container);
}

/// Unified function to split an inline container (Paragraph/Link/...) at cursor.
///
/// Finds the current fragment (can be a direct child of the container, or
/// a child of a Link that is a child of the container) and splits at that point.
/// All subsequent content is moved to a new Paragraph after the container.
bool _splitInlineContainer(
  FluentDocument document,
  InlineContainerNode container,
) {
  final root = document.content;
  final cursor = document.cursor;

  final parent = findParent(root, container as FNode);
  if (parent == null) return false;

  final currentFrag = findNode(root, (n) => n.id == cursor.anchorId) as Fragment?;

  if (currentFrag == null) {
    return _insertNewParagraphAfter(document, container);
  }

  final offset = cursor.anchorOffset;

  var containerIndex = -1;
  Link? insideLink;
  var linkChildIndex = -1;

  for (var i = 0; i < container.fragments.length; i++) {
    final f = container.fragments[i];
    if (f == currentFrag) {
      containerIndex = i;
      break;
    }
    if (f is Link) {
      for (var j = 0; j < f.fragments.length; j++) {
        if (f.fragments[j] == currentFrag) {
          containerIndex = i;
          insideLink = f;
          linkChildIndex = j;
          break;
        }
      }
      if (containerIndex >= 0) break;
    }
  }

  if (containerIndex < 0) {
    return _insertNewParagraphAfter(document, container);
  }

  final text = currentFrag.text;
  final beforeText = text.substring(0, offset);
  final afterText = text.substring(offset);

  final containerParagraph = container as Paragraph;
  final containerStyle = containerParagraph.getStyle();
  final newStyleName = containerStyle.name.startsWith('heading')
      ? 'normal'
      : containerParagraph.styleName;

  final newParagraph = Paragraph(
    textAlign: containerParagraph.textAlign,
    indent: containerParagraph.indent,
    styleName: newStyleName,
  );
  final defaultFrag = newParagraph.fragments.first;
  removeNode(newParagraph, defaultFrag);

  final firstNewFrag = FragmentOperations.cloneFragment(currentFrag, text: afterText);
  appendChild(newParagraph, firstNewFrag);

  currentFrag.text = beforeText;

  if (insideLink != null) {
    final linkChildren = insideLink.fragments.toList();
    for (var j = linkChildIndex + 1; j < linkChildren.length; j++) {
      final c = linkChildren[j];
      if (c is Fragment) {
        removeNode(root, c);
        appendChild(newParagraph, c);
      }
    }
  }

  final containerChildren = container.fragments.toList();
  for (var i = containerIndex + 1; i < containerChildren.length; i++) {
    final f = containerChildren[i];
    removeNode(root, f);
    appendChild(newParagraph, f);
  }

  insertAfter(parent, container as FNode, newParagraph);

  cursor.moveTo(firstNewFrag.id, 0);

  document.updateContent();
  return true;
}

/// Inserts a new empty paragraph after the specified container.
bool _insertNewParagraphAfter(
  FluentDocument document,
  InlineContainerNode container,
) {
  final root = document.content;
  final cursor = document.cursor;

  final parent = findParent(root, container as FNode);
  if (parent == null) return false;

  final textAlign = container is Paragraph ? container.textAlign : 'left';
  final indent = container is Paragraph ? container.indent : 0;
  final styleName = container is Paragraph ? container.styleName : null;
  final containerStyle = container is Paragraph ? container.getStyle() : null;
  final newStyleName = containerStyle?.name.startsWith('heading') == true
      ? 'normal'
      : styleName;
  final newParagraph = Paragraph(
    textAlign: textAlign,
    indent: indent,
    styleName: newStyleName,
  );
  final firstFrag = newParagraph.fragments.first as Fragment;
  firstFrag.fontFamily = document.pendingFontFamily;
  firstFrag.fontSize = document.pendingFontSize;
  firstFrag.styles = List.from(document.pendingStyles);
  firstFrag.color = document.pendingColor;
  firstFrag.highlightColor = document.pendingHighlightColor;

  insertAfter(parent, container as FNode, newParagraph);

  cursor.moveTo(firstFrag.id, 0);
  document.updateContent();
  return true;
}
