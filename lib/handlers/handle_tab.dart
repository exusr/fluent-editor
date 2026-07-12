import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/utils/node_operations.dart';

/// Handles the TAB and SHIFT+TAB keys.
///
/// Lists:
///   - TAB: indent (moves item as sub-item of the previous one)
///   - SHIFT+TAB: outdent (promotes to the upper level)
///
/// Tables:
///   - TAB: moves to the next cell (creates new row if needed)
///   - SHIFT+TAB: moves to the previous cell
///
/// Paragraphs:
///   - TAB: increases indentation (max 10)
///   - SHIFT+TAB: decreases indentation (min 0)
/// Executes outdent of the current ListItem (also used by Enter on empty item).
bool executeHandleOutdent(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;
  final container = document.findLogicalContainerCached(cursor.anchorId);
  if (container == null) return false;
  final ancestorItem = findAncestor<ListItem>(root, container as FNode);
  if (ancestorItem == null) return false;
  return executeHandleOutdentItem(document, ancestorItem);
}

/// Executes outdent of a specific ListItem (avoids re-discovery from cursor).
bool executeHandleOutdentItem(FluentDocument document, ListItem item) {
  return _handleListOutdent(document, item);
}

bool executeHandleTab(FluentDocument document, {bool shift = false}) {
  final root = document.content;
  final cursor = document.cursor;

  final container = document.findLogicalContainerCached(cursor.anchorId);
  if (container == null) return true;

  final containerNode = container as FNode;
  final ancestorItem = findAncestor<ListItem>(root, containerNode);
  if (ancestorItem != null) {
    shift
        ? _handleListOutdent(document, ancestorItem)
        : _handleListIndent(document, ancestorItem);
    return true;
  }

  final ancestorCell = findAncestor<FluentCell>(root, containerNode);
  if (ancestorCell != null) {
    shift
        ? _handleTablePreviousCell(document, ancestorCell)
        : _handleTableNextCell(document, ancestorCell);
    return true;
  }

  if (container is Paragraph) {
    shift
        ? _handleParagraphOutdent(document, container)
        : _handleParagraphIndent(document, container);
    return true;
  }

  return true;
}

/// Indent: moves the current item as a sub-item of the previous one.
bool _handleListIndent(FluentDocument document, ListItem currentItem) {
  final root = document.content;

  final listParent = findParent(root, currentItem);
  if (listParent == null || listParent is! FluentList) return false;

  final currentIndex = listParent.items.indexOf(currentItem);
  if (currentIndex <= 0) return false; // First item, cannot indent

  final prevItem = listParent.items[currentIndex - 1];

  FluentList? existingSublist;
  for (final fragment in prevItem.fragments) {
    if (fragment is FluentList) {
      existingSublist = fragment;
      break;
    }
  }

  removeNode(root, currentItem);

  if (existingSublist != null) {
    appendChild(existingSublist, currentItem);
  } else {
    final newSublist = FluentList(listType: listParent.listType);
    appendChild(prevItem, newSublist);
    appendChild(newSublist, currentItem);
  }

  mergeConsecutiveLists(root);
  recalculateAndUpdate(document);
  return true;
}

/// Outdent: promotes the item to the upper level.
bool _handleListOutdent(FluentDocument document, ListItem currentItem) {
  final root = document.content;

  final listParent = findParent(root, currentItem);
  if (listParent == null || listParent is! FluentList) return false;

  final grandparent = findParent(root, listParent);
  if (grandparent == null) return false;

  final cursor = document.cursor;
  final savedFragId = cursor.anchorId;
  final savedOffset = cursor.anchorOffset;

  if (grandparent is ListItem) {
    final greatGrandparent = findParent(root, grandparent);
    if (greatGrandparent == null || greatGrandparent is! FluentList) return false;

    final currentIndexInSub = listParent.items.indexOf(currentItem);
    final itemsAfter = (currentIndexInSub >= 0)
        ? listParent.items.sublist(currentIndexInSub + 1).toList()
        : <ListItem>[];

    removeNode(root, currentItem);
    for (final item in itemsAfter) {
      removeNode(root, item);
    }

    if (greatGrandparent.items.isNotEmpty) {
      currentItem.bulletType = greatGrandparent.items.first.bulletType;
    }

    if (itemsAfter.isNotEmpty) {
      final newSublist = FluentList(listType: listParent.listType);
      for (final item in itemsAfter) {
        appendChild(newSublist, item);
      }
      appendChild(currentItem, newSublist);
    }

    final parentIndex = greatGrandparent.items.indexOf(grandparent);
    if (parentIndex >= 0) {
      greatGrandparent.items.insert(parentIndex + 1, currentItem);
    }

    if (listParent.items.isEmpty) {
      removeNode(root, listParent);
    }

    recalculateListIndices(root);

    mergeConsecutiveLists(root);

    final originalFrag = document.nodeById(savedFragId);
    if (originalFrag is Fragment) {
      cursor.moveTo(savedFragId, savedOffset.clamp(0, originalFrag.text.length));
    } else {
      final firstParagraph = currentItem.children.whereType<Paragraph>().firstOrNull;
      if (firstParagraph != null && firstParagraph.fragments.isNotEmpty) {
        final lastFrag = firstParagraph.fragments.last;
        if (lastFrag is Fragment) {
          cursor.moveTo(lastFrag.id, lastFrag.text.length);
        }
      }
    }

    document.updateContent();
    return true;
  }

  final newParagraph = outdentListItemToParagraph(root, listParent, currentItem);
  if (newParagraph == null) return false;

  final originalFrag = document.nodeById(savedFragId);
  if (originalFrag != null) {
    cursor.moveTo(savedFragId, savedOffset.clamp(0, (originalFrag as Fragment).text.length));
  } else if (newParagraph.fragments.isNotEmpty) {
    final lastFrag = newParagraph.fragments.last;
    if (lastFrag is Fragment) {
      cursor.moveTo(lastFrag.id, lastFrag.text.length);
    }
  }

  document.updateContent();
  return true;
}

const int _maxIndent = 10;
const int _indentStep = 1;

/// Increases the paragraph indentation (max 10).
bool _handleParagraphIndent(FluentDocument document, Paragraph paragraph) {
  if (paragraph.indent < _maxIndent) {
    paragraph.indent = (paragraph.indent + _indentStep).clamp(0, _maxIndent);
    document.updateContent();
  }
  return true;
}

/// Decreases the paragraph indentation (min 0).
bool _handleParagraphOutdent(FluentDocument document, Paragraph paragraph) {
  if (paragraph.indent > 0) {
    paragraph.indent = (paragraph.indent - _indentStep).clamp(0, _maxIndent);
    document.updateContent();
  }
  return true;
}

/// Moves the cursor to the next cell (right, then down).
/// If last cell, creates a new row.
bool _handleTableNextCell(FluentDocument document, FluentCell currentCell) {
  final root = document.content;
  final cursor = document.cursor;

  final row = findParent(root, currentCell);
  if (row == null || row is! FluentRow) return false;

  final table = findParent(root, row);
  if (table == null || table is! FluentTable) return false;

  final rowIndex = table.rows.indexOf(row);
  final cellIndex = row.cells.indexOf(currentCell);

  if (rowIndex < 0 || cellIndex < 0) return false;

  if (cellIndex < row.cells.length - 1) {
    final nextCell = row.cells[cellIndex + 1];
    return _moveCursorToCell(cursor, nextCell);
  }

  if (rowIndex < table.rows.length - 1) {
    final nextRow = table.rows[rowIndex + 1];
    if (nextRow.cells.isNotEmpty) {
      return _moveCursorToCell(cursor, nextRow.cells.first);
    }
  }

  return _createNewRowInTable(document, table, row);
}

/// Moves the cursor to the previous cell (left, then up).
bool _handleTablePreviousCell(FluentDocument document, FluentCell currentCell) {
  final root = document.content;
  final cursor = document.cursor;

  final row = findParent(root, currentCell);
  if (row == null || row is! FluentRow) return false;

  final table = findParent(root, row);
  if (table == null || table is! FluentTable) return false;

  final rowIndex = table.rows.indexOf(row);
  final cellIndex = row.cells.indexOf(currentCell);

  if (rowIndex < 0 || cellIndex < 0) return false;

  if (cellIndex > 0) {
    final prevCell = row.cells[cellIndex - 1];
    return _moveCursorToCell(cursor, prevCell, toEnd: true);
  }

  if (rowIndex > 0) {
    final prevRow = table.rows[rowIndex - 1];
    if (prevRow.cells.isNotEmpty) {
      return _moveCursorToCell(cursor, prevRow.cells.last, toEnd: true);
    }
  }

  return false;
}

/// Moves the cursor to the start or end of a cell.
bool _moveCursorToCell(Cursor cursor, FluentCell cell, {bool toEnd = false}) {
  final leaves = FragmentOperations.collectLeafFragments(cell);
  if (leaves.isNotEmpty) {
    final target = toEnd ? leaves.last : leaves.first;
    cursor.moveTo(target.id, toEnd ? target.text.length : 0);
    return true;
  }
  final emptyFrag = Fragment('');
  appendChild(cell, emptyFrag);
  cursor.moveTo(emptyFrag.id, 0);
  return true;
}

/// Creates a new row at the bottom of the table and positions the cursor in the first cell.
bool _createNewRowInTable(
  FluentDocument document,
  FluentTable table,
  FluentRow lastRow,
) {
  final cursor = document.cursor;

  final numCols = lastRow.cells.length;
  if (numCols == 0) return false;

  final newCells = <FluentCell>[];
  for (var i = 0; i < numCols; i++) {
    final emptyFrag = FragmentOperations.createFragmentWithPendingStyles(document, '');
    final paragraph = Paragraph()..fragments = [emptyFrag];
    final cell = FluentCell(children: [paragraph]);
    newCells.add(cell);
  }

  final newRow = FluentRow(cells: newCells);
  appendChild(table, newRow);

  return _moveCursorToCell(cursor, newCells.first);
}