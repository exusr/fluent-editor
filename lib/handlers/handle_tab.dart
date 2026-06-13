import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
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
  final container = findLogicalContainer(root, cursor.anchorId);
  if (container == null) return false;
  final ancestorItem = _findAncestor<ListItem>(root, container as FNode);
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

  // Find the current cursor container
  final container = findLogicalContainer(root, cursor.anchorId);
  if (container == null) return true;

  // Climb up to find ListItem/Cell ancestor (with the new structure the
  // returned container is the inner Paragraph, not the ListItem/Cell).
  final containerNode = container as FNode;
  final ancestorItem = _findAncestor<ListItem>(root, containerNode);
  if (ancestorItem != null) {
    shift
        ? _handleListOutdent(document, ancestorItem)
        : _handleListIndent(document, ancestorItem);
    return true;
  }

  final ancestorCell = _findAncestor<FluentCell>(root, containerNode);
  if (ancestorCell != null) {
    shift
        ? _handleTablePreviousCell(document, ancestorCell)
        : _handleTableNextCell(document, ancestorCell);
    return true;
  }

  // Normal paragraphs: handle indent/outdent
  if (container is Paragraph) {
    shift
        ? _handleParagraphOutdent(document, container)
        : _handleParagraphIndent(document, container);
    return true;
  }

  return true;
}

/// Climbs the tree looking for an ancestor of type [T].
T? _findAncestor<T extends FNode>(Root root, FNode node) {
  FNode? current = node;
  while (current != null) {
    if (current is T) return current;
    current = findParent(root, current);
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
// LISTS - Indent / Outdent
// ═══════════════════════════════════════════════════════════════════════

/// Indent: moves the current item as a sub-item of the previous one.
bool _handleListIndent(FluentDocument document, ListItem currentItem) {
  final root = document.content;

  // Find the parent FluentList
  final listParent = findParent(root, currentItem);
  if (listParent == null || listParent is! FluentList) return false;

  // Find the index of the current item
  final currentIndex = listParent.items.indexOf(currentItem);
  if (currentIndex <= 0) return false; // First item, cannot indent

  // Find the previous item
  final prevItem = listParent.items[currentIndex - 1];

  // Check if the previous item already has a sublist
  FluentList? existingSublist;
  for (final fragment in prevItem.fragments) {
    if (fragment is FluentList) {
      existingSublist = fragment;
      break;
    }
  }

  // Remove the current item from the parent list
  removeNode(root, currentItem);

  if (existingSublist != null) {
    // Add to the existing sublist
    appendChild(existingSublist, currentItem);
  } else {
    // Create a new sublist
    final newSublist = FluentList(listType: listParent.listType);
    appendChild(prevItem, newSublist);
    appendChild(newSublist, currentItem);
  }

  // Merge consecutive lists with the same type
  mergeConsecutiveLists(root);
  // Recalculate the indices
  recalculateListIndices(root);

  // Keep the cursor in the same position
  document.updateContent();
  return true;
}

/// Outdent: promotes the item to the upper level.
bool _handleListOutdent(FluentDocument document, ListItem currentItem) {
  final root = document.content;

  // Find the parent FluentList
  final listParent = findParent(root, currentItem);
  if (listParent == null || listParent is! FluentList) return false;

  // Find the parent of the list
  final grandparent = findParent(root, listParent);
  if (grandparent == null) return false;

  // Save the cursor position before mutating the tree
  final cursor = document.cursor;
  final savedFragId = cursor.anchorId;
  final savedOffset = cursor.anchorOffset;

  // If the list is inside a ListItem (sublist), promote to the upper level
  // (Google Docs behavior: subsequent items become sublist of currentItem).
  if (grandparent is ListItem) {
    final greatGrandparent = findParent(root, grandparent);
    if (greatGrandparent == null || greatGrandparent is! FluentList) return false;

    // Items of the sublist AFTER currentItem: will become sublist of currentItem
    final currentIndexInSub = listParent.items.indexOf(currentItem);
    final itemsAfter = (currentIndexInSub >= 0)
        ? listParent.items.sublist(currentIndexInSub + 1).toList()
        : <ListItem>[];

    // Remove currentItem and subsequent items from the sublist
    removeNode(root, currentItem);
    for (final item in itemsAfter) {
      removeNode(root, item);
    }

    // Inherit bulletType from the upper level (e.g., • instead of ◦)
    if (greatGrandparent.items.isNotEmpty) {
      currentItem.bulletType = greatGrandparent.items.first.bulletType;
    }

    // If there are subsequent items, they become a new sublist of currentItem
    // (preserves the visual hierarchy like Google Docs)
    if (itemsAfter.isNotEmpty) {
      final newSublist = FluentList(listType: listParent.listType);
      for (final item in itemsAfter) {
        appendChild(newSublist, item);
      }
      appendChild(currentItem, newSublist);
    }

    // Insert currentItem after the grandparent (parent ListItem) in the upper list
    final parentIndex = greatGrandparent.items.indexOf(grandparent);
    if (parentIndex >= 0) {
      greatGrandparent.items.insert(parentIndex + 1, currentItem);
    }

    // If the original sublist is now empty, remove it from the grandparent
    if (listParent.items.isEmpty) {
      removeNode(root, listParent);
    }

    recalculateListIndices(root);

    // Merge consecutive lists with the same type
    mergeConsecutiveLists(root);

    // Restore the cursor position (the original fragment survives)
    final originalFrag = findById(root, savedFragId);
    if (originalFrag is Fragment) {
      cursor.moveTo(savedFragId, savedOffset.clamp(0, originalFrag.text.length));
    } else {
      // Fallback: end of text of the first paragraph of currentItem
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

  // First level: transform to paragraph (exits the list like Google Docs)
  final newParagraph = outdentListItemToParagraph(root, listParent, currentItem);
  if (newParagraph == null) return false;

  // Restore the cursor position: try the original fragment first
  // (it might still exist in the newParagraph), otherwise go to the end.
  final originalFrag = findById(root, savedFragId);
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

// ═══════════════════════════════════════════════════════════════════════
// PARAGRAPHS - Indent / Outdent
// ═══════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════
// TABLES - Cell navigation
// ═══════════════════════════════════════════════════════════════════════

/// Moves the cursor to the next cell (right, then down).
/// If last cell, creates a new row.
bool _handleTableNextCell(FluentDocument document, FluentCell currentCell) {
  final root = document.content;
  final cursor = document.cursor;

  // Find the row and the table
  final row = findParent(root, currentCell);
  if (row == null || row is! FluentRow) return false;

  final table = findParent(root, row);
  if (table == null || table is! FluentTable) return false;

  final rowIndex = table.rows.indexOf(row);
  final cellIndex = row.cells.indexOf(currentCell);

  if (rowIndex < 0 || cellIndex < 0) return false;

  // Look for the next cell in the same row
  if (cellIndex < row.cells.length - 1) {
    // There's a next cell in the same row
    final nextCell = row.cells[cellIndex + 1];
    return _moveCursorToCellStart(cursor, nextCell);
  }

  // We're in the last cell of the row, move to the next row
  if (rowIndex < table.rows.length - 1) {
    final nextRow = table.rows[rowIndex + 1];
    if (nextRow.cells.isNotEmpty) {
      return _moveCursorToCellStart(cursor, nextRow.cells.first);
    }
  }

  // We're in the last cell of the last row, create a new row
  return _createNewRowInTable(document, table, row);
}

/// Moves the cursor to the previous cell (left, then up).
bool _handleTablePreviousCell(FluentDocument document, FluentCell currentCell) {
  final root = document.content;
  final cursor = document.cursor;

  // Find the row and the table
  final row = findParent(root, currentCell);
  if (row == null || row is! FluentRow) return false;

  final table = findParent(root, row);
  if (table == null || table is! FluentTable) return false;

  final rowIndex = table.rows.indexOf(row);
  final cellIndex = row.cells.indexOf(currentCell);

  if (rowIndex < 0 || cellIndex < 0) return false;

  // Look for the previous cell in the same row
  if (cellIndex > 0) {
    final prevCell = row.cells[cellIndex - 1];
    return _moveCursorToCellEnd(cursor, prevCell);
  }

  // We're in the first cell, move to the previous row
  if (rowIndex > 0) {
    final prevRow = table.rows[rowIndex - 1];
    if (prevRow.cells.isNotEmpty) {
      return _moveCursorToCellEnd(cursor, prevRow.cells.last);
    }
  }

  // We're in the first cell of the first row, do nothing
  return false;
}

/// Moves the cursor to the start of a cell.
bool _moveCursorToCellStart(Cursor cursor, FluentCell cell) {
  final leaves = FragmentOperations.collectLeafFragments(cell);
  if (leaves.isNotEmpty) {
    cursor.moveTo(leaves.first.id, 0);
    return true;
  }
  // Create an empty fragment if necessary
  final emptyFrag = Fragment('');
  appendChild(cell, emptyFrag);
  cursor.moveTo(emptyFrag.id, 0);
  return true;
}

/// Moves the cursor to the end of a cell.
bool _moveCursorToCellEnd(Cursor cursor, FluentCell cell) {
  final leaves = FragmentOperations.collectLeafFragments(cell);
  if (leaves.isNotEmpty) {
    final last = leaves.last;
    cursor.moveTo(last.id, last.text.length);
    return true;
  }
  // Create an empty fragment if necessary
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

  // Determine the number of columns from the previous row
  final numCols = lastRow.cells.length;
  if (numCols == 0) return false;

  // Create the new row with empty cells
  final newCells = <FluentCell>[];
  for (var i = 0; i < numCols; i++) {
    final emptyFrag = FragmentOperations.createFragmentWithPendingStyles(document, '');
    final paragraph = Paragraph()..fragments = [emptyFrag];
    final cell = FluentCell(children: [paragraph]);
    newCells.add(cell);
  }

  final newRow = FluentRow(cells: newCells);
  appendChild(table, newRow);

  // Position the cursor in the first cell of the new row
  return _moveCursorToCellStart(cursor, newCells.first);
}