import 'dart:math' as math;

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/renderers/render_fluent_node.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/editor/fluent_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ─── Handle sizes ─────────────────────────────────────────────────────
const double _kHandleHitSize  = 8.0;  // clickable area of the handle
const double _kMinColWidth     = 30.0;
const double _kMinRowHeight    = 20.0;

class FluentTableWidget extends StatefulWidget {
  const FluentTableWidget({super.key, required this.node, required this.document});

  final FluentTable node;
  final FluentDocument document;

  @override
  State<FluentTableWidget> createState() => _FluentTableWidgetState();
}

class _FluentTableWidgetState extends State<FluentTableWidget> {
  final GlobalKey _tableKey = GlobalKey();
  List<double> _renderedRowHeights = [];  // updated after every frame

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _readRowHeights());
  }

  void _readRowHeights() {
    if (!mounted) return;
    final ro = _tableKey.currentContext?.findRenderObject();
    if (ro is RenderFluentTable) {
      final h = ro.computedRowHeights;
      if (h.isNotEmpty && h != _renderedRowHeights) {
        setState(() => _renderedRowHeights = List.from(h));
      }
    }
  }

  // ── Calculate number of columns ─────────────────────────────────────────
  int get _numCols {
    int n = 0;
    for (final row in widget.node.rows) {
      int rc = 0;
      for (final cell in row.cells) {
        rc += cell.colSpan;
      }
      if (rc > n) n = rc;
    }
    return n;
  }

  // ── Actual table width (saved or full available) ────
  double _tableWidth(double availableWidth) {
    final saved = widget.node.tableWidth;
    if (saved != null) return math.min(saved, availableWidth);
    return availableWidth;
  }

  // ── Current widths (or uniform if not yet set) ────────
  List<double> _colWidths(double tableWidth) {
    final n = _numCols;
    if (n == 0) return [];
    final saved = widget.node.columnWidths;
    if (saved != null && saved.length == n) return List.from(saved);
    final base = math.max(tableWidth / n, _kMinColWidth);
    return List.filled(n, base);
  }

  // ── Table drag (right border) ──────────────────────────────────────
  void _onTableDragUpdate(DragUpdateDetails details, double availableWidth) {
    final current = widget.node.tableWidth ?? availableWidth;
    final newWidth = math.max(current + details.delta.dx, _kMinColWidth * _numCols);
    widget.node.tableWidth = math.min(newWidth, availableWidth);
    widget.document.updateContent();
    // Force complete layout rebuild to maintain center alignment
    if (mounted) {
      setState(() {});
      // Force recalculation of the table render object
      final ro = _tableKey.currentContext?.findRenderObject();
      if (ro is RenderFluentTable) {
        ro.markNeedsLayout();
      }
      // Also force recalculation of the parent (Center widget)
      final parentContext = _tableKey.currentContext;
      parentContext?.findRenderObject()?.markNeedsLayout();
      // Triple rebuild to ensure complete recalculation
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
          // Force parent layout again
          parentContext?.findRenderObject()?.markNeedsLayout();
        }
      });
    }
  }

  // ── Column drag ────────────────────────────────────────────────────
  void _onColDragUpdate(int colIdx, DragUpdateDetails details, double tableWidth) {
    final widths = _colWidths(tableWidth);
    final delta = details.delta.dx;
    final newWidth = math.max(widths[colIdx] + delta, _kMinColWidth);
    widths[colIdx] = newWidth;
    widget.node.columnWidths = widths;
    widget.document.updateContent();
  }

  // ── Row drag (minHeight only) ──────────────────────────────────────
  void _onRowDragUpdate(int rowIdx, DragUpdateDetails details) {
    final row = widget.node.rows[rowIdx];
    final delta = details.delta.dy;
    final current = row.rowHeight ?? _kMinRowHeight;
    row.rowHeight = math.max(current + delta, _kMinRowHeight);
    widget.document.updateContent();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final availableWidth = constraints.maxWidth;
      final tWidth = _tableWidth(availableWidth);
      final colWidths = _colWidths(tWidth);
      final numCols = colWidths.length;
      if (numCols == 0) return const SizedBox.shrink();

      return Padding(
        padding: EdgeInsets.only(
          top: widget.document.pendingSpacingBefore,
          bottom: widget.document.pendingSpacingAfter,
        ),
        child: Center(
          child: SizedBox(
            width: tWidth,
            child: _TableWithHandles(
              tableKey: _tableKey,
              node: widget.node,
              document: widget.document,
              colWidths: colWidths,
              availableWidth: availableWidth,
              tableWidth: tWidth,
              renderedRowHeights: _renderedRowHeights,
              onColDragUpdate: (i, d) => _onColDragUpdate(i, d, tWidth),
              onRowDragUpdate: (i, d) => _onRowDragUpdate(i, d),
              onTableDragUpdate: (d) => _onTableDragUpdate(d, availableWidth),
              onLayoutComplete: _readRowHeights,
            ),
          ),
        ),
      );
    });
  }
}

// ─── Widget that combines table + drag handles ─────────────────────────
// Handles appear only when the cursor is near the border
// and no text selection is in progress.
class _TableWithHandles extends StatefulWidget {
  const _TableWithHandles({
    required this.tableKey,
    required this.node,
    required this.document,
    required this.colWidths,
    required this.availableWidth,
    required this.tableWidth,
    required this.renderedRowHeights,
    required this.onColDragUpdate,
    required this.onRowDragUpdate,
    required this.onTableDragUpdate,
    required this.onLayoutComplete,
  });

  final GlobalKey tableKey;
  final FluentTable node;
  final FluentDocument document;
  final List<double> colWidths;
  final double availableWidth;
  final double tableWidth;
  final List<double> renderedRowHeights;
  final void Function(int, DragUpdateDetails) onColDragUpdate;
  final void Function(int, DragUpdateDetails) onRowDragUpdate;
  final void Function(DragUpdateDetails) onTableDragUpdate;
  final VoidCallback onLayoutComplete;

  @override
  State<_TableWithHandles> createState() => _TableWithHandlesState();
}

class _TableWithHandlesState extends State<_TableWithHandles> {
  int _hoveredCol = -1;
  int _hoveredRow = -1;
  int _draggingCol = -1;
  int _draggingRow = -1;
  bool _hoveredTable = false;
  bool _draggingTable = false;

  bool _hasActiveSelection = false;
  FluentCell? _clickedCell;

  @override
  void initState() {
    super.initState();
    widget.document.cursor.addListener(_onCursorChange);
    _hasActiveSelection = !widget.document.cursor.isCollapsed;
  }

  @override
  void didUpdateWidget(_TableWithHandles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.cursor != widget.document.cursor) {
      oldWidget.document.cursor.removeListener(_onCursorChange);
      widget.document.cursor.addListener(_onCursorChange);
    }
  }

  @override
  void dispose() {
    widget.document.cursor.removeListener(_onCursorChange);
    super.dispose();
  }

  void _onCursorChange() {
    final active = !widget.document.cursor.isCollapsed;
    if (active != _hasActiveSelection) {
      setState(() => _hasActiveSelection = active);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapDown: (details) {
            _clickedCell = _findCellAtPosition(details.globalPosition);
            _showContextMenu(details.globalPosition);
          },
          onLongPressStart: (details) {
            _clickedCell = _findCellAtPosition(details.globalPosition);
            _showContextMenu(details.globalPosition);
          },
          child: _NotifyingTableRenderer(
            tableKey: widget.tableKey,
            node: widget.node,
            document: widget.document,
            colWidths: widget.colWidths,
            availableWidth: widget.availableWidth,
            onLayout: widget.onLayoutComplete,
          ),
        ),
        // Column handles — always present to intercept hover
        ..._buildColHandles(),
        // Row handles — always present to intercept hover
        ..._buildRowHandles(),
        // Table right border handle
        _buildTableRightHandle(),
      ],
    );
  }

  // Returns the cell containing globalPosition.
  //
  // Instead of relying on the render children iteration order
  // (unreliable after cell insert/remove), reconstructs the bounds of each
  // cell directly from the data model using the same colOffsets/rowOffsets
  // that the render object calculates in performLayout.
  // With rowspan/colspan, multiple cells overlap geometrically:
  // we choose the one with rowSpan==1 && colSpan==1 if it exists, otherwise
  // the one with the smallest area (the most specific).
  FluentCell? _findCellAtPosition(Offset globalPosition) {
    final tableContext = widget.tableKey.currentContext;
    if (tableContext == null) return null;

    final tableBox = tableContext.findRenderObject();
    if (tableBox is! RenderFluentTable) return null;

    final localPosition = tableBox.globalToLocal(globalPosition);

    // ── Reconstruct colOffsets and rowOffsets from data model ──────────
    final colWidths = widget.colWidths;
    if (colWidths.isEmpty) return null;

    final List<double> colOffsets = [];
    double cx = 0;
    for (final w in colWidths) {
      colOffsets.add(cx);
      cx += w;
    }

    final renderedHeights = widget.renderedRowHeights;
    final List<double> rowOffsets = [];
    double ry = 0;
    for (int r = 0; r < widget.node.rows.length; r++) {
      rowOffsets.add(ry);
      final h = (r < renderedHeights.length)
          ? renderedHeights[r]
          : (widget.node.rows[r].rowHeight ?? _kMinRowHeight);
      ry += h;
    }

    // ── Find the most specific cell containing the point ─────────────
    FluentCell? bestCell;
    double bestArea = double.infinity;

    for (int r = 0; r < widget.node.rows.length; r++) {
      final row = widget.node.rows[r];
      // Current logical column (accounts for colSpan of previous cells)
      int logicalCol = 0;
      for (int c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];

        // Offset X: use the logical column
        if (logicalCol >= colOffsets.length) {
          logicalCol += cell.colSpan;
          continue;
        }
        final double x = colOffsets[logicalCol];
        final double y = rowOffsets[r];

        // Width = sum of covered columns
        double cellWidth = 0;
        for (int ci = logicalCol;
            ci < math.min(logicalCol + cell.colSpan, colOffsets.length);
            ci++) {
          cellWidth += colWidths[ci];
        }

        // Height = sum of covered rows
        double cellHeight = 0;
        for (int ri = r;
            ri < math.min(r + cell.rowSpan, widget.node.rows.length);
            ri++) {
          cellHeight += (ri < renderedHeights.length)
              ? renderedHeights[ri]
              : (widget.node.rows[ri].rowHeight ?? _kMinRowHeight);
        }

        final rect = Rect.fromLTWH(x, y, cellWidth, cellHeight);
        if (rect.contains(localPosition)) {
          final area = cellWidth * cellHeight;
          if (area < bestArea) {
            bestArea = area;
            bestCell = cell;
          }
        }

        logicalCol += cell.colSpan;
      }
    }

    return bestCell;
  }

  List<Widget> _buildColHandles() {
    final handles = <Widget>[];
    double x = 0;
    for (int i = 0; i < widget.colWidths.length - 1; i++) {
      x += widget.colWidths[i];
      final capturedI = i;
      final isHovered = _hoveredCol == capturedI;
      final isDragging = _draggingCol == capturedI;
      final showIndicator = (isHovered || isDragging) && !_hasActiveSelection;

      handles.add(Positioned(
        left: x - _kHandleHitSize / 2,
        top: 0,
        bottom: 0,
        width: _kHandleHitSize,
        child: MouseRegion(
          cursor: (!_hasActiveSelection)
              ? SystemMouseCursors.resizeColumn
              : MouseCursor.defer,
          onEnter: (_) => setState(() => _hoveredCol = capturedI),
          onExit: (_) {
            if (_draggingCol != capturedI) {
              setState(() => _hoveredCol = -1);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _hasActiveSelection
                ? null
                : (_) => setState(() => _draggingCol = capturedI),
            onHorizontalDragUpdate: _hasActiveSelection
                ? null
                : (d) => widget.onColDragUpdate(capturedI, d),
            onHorizontalDragEnd: _hasActiveSelection
                ? null
                : (_) => setState(() {
                    _draggingCol = -1;
                    _hoveredCol = -1;
                  }),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(color: Colors.transparent),
                if (showIndicator)
                  Center(
                    child: Container(
                      width: 2,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ));
    }
    return handles;
  }

  List<Widget> _buildRowHandles() {
    final handles = <Widget>[];
    final heights = (widget.renderedRowHeights.length == widget.node.rows.length)
        ? widget.renderedRowHeights
        : widget.node.rows.map((r) => r.rowHeight ?? _kMinRowHeight).toList();
    double y = 0;
    for (int i = 0; i < widget.node.rows.length - 1; i++) {
      y += heights[i];
      final capturedI = i;
      final isHovered = _hoveredRow == capturedI;
      final isDragging = _draggingRow == capturedI;
      final showIndicator = (isHovered || isDragging) && !_hasActiveSelection;

      handles.add(Positioned(
        left: 0,
        right: 0,
        top: y - _kHandleHitSize / 2,
        height: _kHandleHitSize,
        child: MouseRegion(
          cursor: (!_hasActiveSelection)
              ? SystemMouseCursors.resizeRow
              : MouseCursor.defer,
          onEnter: (_) => setState(() => _hoveredRow = capturedI),
          onExit: (_) {
            if (_draggingRow != capturedI) {
              setState(() => _hoveredRow = -1);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: _hasActiveSelection
                ? null
                : (_) => setState(() => _draggingRow = capturedI),
            onVerticalDragUpdate: _hasActiveSelection
                ? null
                : (d) => widget.onRowDragUpdate(capturedI, d),
            onVerticalDragEnd: _hasActiveSelection
                ? null
                : (_) => setState(() {
                    _draggingRow = -1;
                    _hoveredRow = -1;
                  }),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(color: Colors.transparent),
                if (showIndicator)
                  Center(
                    child: Container(
                      height: 2,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ));
    }
    return handles;
  }

  Widget _buildTableRightHandle() {
    final showIndicator = (_hoveredTable || _draggingTable) && !_hasActiveSelection;
    return Positioned(
      right: -_kHandleHitSize / 2,
      top: 0,
      bottom: 0,
      width: _kHandleHitSize,
      child: MouseRegion(
        cursor: !_hasActiveSelection
            ? SystemMouseCursors.resizeColumn
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hoveredTable = true),
        onExit: (_) {
          if (!_draggingTable) setState(() => _hoveredTable = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _hasActiveSelection
              ? null
              : (_) => setState(() => _draggingTable = true),
          onHorizontalDragUpdate: _hasActiveSelection
              ? null
              : widget.onTableDragUpdate,
          onHorizontalDragEnd: _hasActiveSelection
              ? null
              : (_) => setState(() {
                  _draggingTable = false;
                  _hoveredTable = false;
                }),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(color: Colors.transparent),
              if (showIndicator)
                Center(
                  child: Container(
                    width: 2,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(Offset globalPosition) {
    final cell = _clickedCell;
    final canIncreaseColspan = cell != null && _canIncreaseColspan(cell);
    final canDecreaseColspan = cell != null && cell.colSpan > 1;
    final canIncreaseRowspan = cell != null && _canIncreaseRowspan(cell);
    final canDecreaseRowspan = cell != null && cell.rowSpan > 1;
    
    showFluentContextMenu(
      context: context,
      globalPosition: globalPosition,
      items: [
        FluentContextMenuItem(
          icon: Icons.table_rows,
          label: widget.document.labels?.insertRowAbove ?? 'Insert row above',
          onPressed: () {
            widget.document.saveState(description: 'Insert table row above', forceNewAction: true);
            _insertRowAbove();
          },
        ),
        FluentContextMenuItem(
          icon: Icons.table_rows,
          label: widget.document.labels?.insertRowBelow ?? 'Insert row below',
          onPressed: () {
            widget.document.saveState(description: 'Insert table row below', forceNewAction: true);
            _insertRowBelow();
          },
        ),
        FluentContextMenuItem(
          icon: Icons.view_column,
          label: 'Insert column',
          onPressed: () {
            widget.document.saveState(description: 'Insert table column', forceNewAction: true);
            _insertColumn();
          },
        ),
        FluentContextMenuItem(
          icon: Icons.delete_outline,
          label: 'Remove row',
          onPressed: widget.node.rows.length > 1 ? () {
            widget.document.saveState(description: 'Remove table row', forceNewAction: true);
            _removeRow();
          } : null,
        ),
        FluentContextMenuItem(
          icon: Icons.delete_outline,
          label: 'Remove column',
          onPressed: _getNumCols() > 1 ? () {
            widget.document.saveState(description: 'Remove table column', forceNewAction: true);
            _removeColumn();
          } : null,
        ),
        FluentContextMenuItem(
          icon: Icons.merge_type,
          label: 'Increase colspan',
          onPressed: canIncreaseColspan ? () {
            widget.document.saveState(description: 'Increase colspan', forceNewAction: true);
            _increaseColspan();
          } : null,
        ),
        FluentContextMenuItem(
          icon: Icons.call_split,
          label: 'Decrease colspan',
          onPressed: canDecreaseColspan ? () {
            widget.document.saveState(description: 'Decrease colspan', forceNewAction: true);
            _decreaseColspan();
          } : null,
        ),
        FluentContextMenuItem(
          icon: Icons.merge_type,
          label: 'Increase rowspan',
          onPressed: canIncreaseRowspan ? () {
            widget.document.saveState(description: 'Increase rowspan', forceNewAction: true);
            _increaseRowspan();
          } : null,
        ),
        FluentContextMenuItem(
          icon: Icons.call_split,
          label: 'Decrease rowspan',
          onPressed: canDecreaseRowspan ? () {
            widget.document.saveState(description: 'Decrease rowspan', forceNewAction: true);
            _decreaseRowspan();
          } : null,
        ),
        FluentContextMenuItem(
          icon: Icons.delete,
          label: 'Delete table',
          onPressed: () {
            widget.document.saveState(description: 'Delete table', forceNewAction: true);
            removeNode(widget.document.content, widget.node);
            widget.document.updateContent();
          },
        ),
      ],
    );
  }

  (int, int)? _findCellPosition(FluentCell cell) {
    for (int r = 0; r < widget.node.rows.length; r++) {
      final row = widget.node.rows[r];
      for (int c = 0; c < row.cells.length; c++) {
        if (row.cells[c] == cell) {
          return (r, c);
        }
      }
    }
    return null;
  }

  // ── Calculate the logical column of a cell given its physical index ──
  int _logicalColOf(int rowIdx, int physicalColIdx) {
    int logical = 0;
    final row = widget.node.rows[rowIdx];
    for (int c = 0; c < physicalColIdx; c++) {
      logical += row.cells[c].colSpan;
    }
    return logical;
  }

  // BUG FIX: also verify that the cell to the right has compatible rowSpan
  bool _canIncreaseColspan(FluentCell cell) {
    for (int r = 0; r < widget.node.rows.length; r++) {
      final row = widget.node.rows[r];
      for (int c = 0; c < row.cells.length; c++) {
        if (row.cells[c] == cell) {
          if (c >= row.cells.length - 1) return false;
          // The cell to the right must have the same rowSpan
          return row.cells[c + 1].rowSpan == cell.rowSpan;
        }
      }
    }
    return false;
  }

  // BUG FIX: also verify that the cell below has compatible colSpan
  bool _canIncreaseRowspan(FluentCell cell) {
    for (int r = 0; r < widget.node.rows.length; r++) {
      final row = widget.node.rows[r];
      for (int c = 0; c < row.cells.length; c++) {
        if (row.cells[c] == cell) {
          final targetRowIdx = r + cell.rowSpan;
          if (targetRowIdx >= widget.node.rows.length) return false;

          // Calculate the logical column of the current cell
          final logicalCol = _logicalColOf(r, c);

          // Find the cell in the target row at the same logical column
          final targetRow = widget.node.rows[targetRowIdx];
          int logicalC = 0;
          for (int tc = 0; tc < targetRow.cells.length; tc++) {
            if (logicalC == logicalCol) {
              // Must have the same colSpan
              return targetRow.cells[tc].colSpan == cell.colSpan;
            }
            logicalC += targetRow.cells[tc].colSpan;
          }
          return false;
        }
      }
    }
    return false;
  }

  int _getNumCols() {
    int n = 0;
    for (final row in widget.node.rows) {
      int rc = 0;
      for (final cell in row.cells) {
        rc += cell.colSpan;
      }
      if (rc > n) n = rc;
    }
    return n;
  }

  void _insertRowAbove() {
    final position = _clickedCell != null ? _findCellPosition(_clickedCell!) : null;
    final insertAtRow = position != null ? position.$1 : widget.node.rows.length;

    final newRow = FluentRow();
    final numCols = _getNumCols();
    for (int i = 0; i < numCols; i++) {
      newRow.cells.add(FluentCell());
    }

    widget.node.rows.insert(insertAtRow, newRow);
    widget.document.updateContent();
  }

  void _insertRowBelow() {
    final position = _clickedCell != null ? _findCellPosition(_clickedCell!) : null;
    final insertAfterRow = position != null ? position.$1 + 1 : widget.node.rows.length;

    final newRow = FluentRow();
    final numCols = _getNumCols();
    for (int i = 0; i < numCols; i++) {
      newRow.cells.add(FluentCell());
    }

    widget.node.rows.insert(insertAfterRow, newRow);
    widget.document.updateContent();
  }

  void _insertColumn() {
    final position = _clickedCell != null ? _findCellPosition(_clickedCell!) : null;

    // BUG FIX: calculate insertAfterLogicalCol as logical column, not physical.
    // When no cell is clicked, insert after the last logical column.
    int insertAfterLogicalCol;
    if (position != null) {
      insertAfterLogicalCol = _logicalColOf(position.$1, position.$2)
          + widget.node.rows[position.$1].cells[position.$2].colSpan;
    } else {
      insertAfterLogicalCol = _getNumCols();
    }

    for (int r = 0; r < widget.node.rows.length; r++) {
      final row = widget.node.rows[r];
      int logicalCol = 0;
      int insertIndex = row.cells.length;

      for (int c = 0; c < row.cells.length; c++) {
        if (logicalCol >= insertAfterLogicalCol) {
          insertIndex = c;
          break;
        }
        logicalCol += row.cells[c].colSpan;
      }

      row.cells.insert(insertIndex, FluentCell());
    }

    widget.document.updateContent();
  }

  // BUG FIX: remove the row of the clicked cell, not always the last one
  void _removeRow() {
    if (widget.node.rows.length <= 1) return;

    final position = _clickedCell != null ? _findCellPosition(_clickedCell!) : null;
    final removeIdx = position != null ? position.$1 : widget.node.rows.length - 1;

    widget.node.rows.removeAt(removeIdx);
    widget.document.updateContent();
  }

  // BUG FIX: remove the column of the clicked cell, not always the last one
  void _removeColumn() {
    if (_getNumCols() <= 1) return;

    final position = _clickedCell != null ? _findCellPosition(_clickedCell!) : null;

    // Logical column to remove
    int removeLogicalCol;
    if (position != null) {
      removeLogicalCol = _logicalColOf(position.$1, position.$2);
    } else {
      removeLogicalCol = _getNumCols() - 1;
    }

    for (final row in widget.node.rows) {
      int logicalCol = 0;
      for (int c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        if (logicalCol <= removeLogicalCol &&
            removeLogicalCol < logicalCol + cell.colSpan) {
          if (cell.colSpan > 1) {
            cell.colSpan--;
          } else {
            row.cells.removeAt(c);
          }
          break;
        }
        logicalCol += cell.colSpan;
      }
    }

    widget.document.updateContent();
  }

  void _increaseColspan() {
    if (_clickedCell == null) return;
    final cell = _clickedCell!;
    final position = _findCellPosition(cell);
    if (position == null) return;

    final rowIdx = position.$1;
    final colIdx = position.$2;
    final row = widget.node.rows[rowIdx];

    // BUG FIX: calculate the LOGICAL column of the current cell
    final logicalColOfCell = _logicalColOf(rowIdx, colIdx);

    // The target column is the one immediately after the end of the current colspan
    final targetLogicalCol = logicalColOfCell + cell.colSpan;

    // Find the cell in the same row at the target logical column
    int logicalCol = 0;
    int cellToAbsorbIndex = -1;

    for (int c = 0; c < row.cells.length; c++) {
      if (logicalCol == targetLogicalCol) {
        cellToAbsorbIndex = c;
        break;
      }
      logicalCol += row.cells[c].colSpan;
    }

    if (cellToAbsorbIndex < 0) return;

    final cellToAbsorb = row.cells[cellToAbsorbIndex];

    // Guard: rowSpan must match (already verified by _canIncreaseColspan,
    // but we repeat for safety)
    if (cellToAbsorb.rowSpan != cell.rowSpan) return;

    // Move content from the cell to be absorbed into the current cell, preserving styles
    _moveCellContent(cellToAbsorb, cell);

    // BUG FIX: sum colspans instead of incrementing by 1
    cell.colSpan += cellToAbsorb.colSpan;

    row.cells.removeAt(cellToAbsorbIndex);

    widget.document.updateContent();
  }

  void _decreaseColspan() {
    if (_clickedCell == null) return;
    final cell = _clickedCell!;
    if (cell.colSpan <= 1) return;

    cell.colSpan--;

    final position = _findCellPosition(cell);
    if (position == null) return;

    final rowIdx = position.$1;
    final colIdx = position.$2;
    final row = widget.node.rows[rowIdx];

    final newCell = FluentCell();
    row.cells.insert(colIdx + 1, newCell);

    widget.document.updateContent();
  }

  void _increaseRowspan() {
    if (_clickedCell == null) return;
    final cell = _clickedCell!;
    final position = _findCellPosition(cell);
    if (position == null) return;

    final rowIdx = position.$1;
    final colIdx = position.$2;

    // BUG FIX: calculate the LOGICAL column of the current cell
    final logicalColOfCell = _logicalColOf(rowIdx, colIdx);

    // The target row is the one immediately below the end of the current rowspan
    final targetRowIdx = rowIdx + cell.rowSpan;

    if (targetRowIdx >= widget.node.rows.length) return;

    final targetRow = widget.node.rows[targetRowIdx];

    // Find the cell in the target row at the same logical column
    int logicalCol = 0;
    int cellBelowIndex = -1;

    for (int c = 0; c < targetRow.cells.length; c++) {
      if (logicalCol == logicalColOfCell) {
        cellBelowIndex = c;
        break;
      }
      logicalCol += targetRow.cells[c].colSpan;
    }

    if (cellBelowIndex < 0) return;

    final cellBelow = targetRow.cells[cellBelowIndex];

    // BUG FIX: colSpan must match (already verified by _canIncreaseRowspan)
    if (cellBelow.colSpan != cell.colSpan) return;

    // Move content from the cell below into the current cell, preserving styles
    _moveCellContent(cellBelow, cell);

    // BUG FIX: sum rowspans instead of incrementing by 1
    cell.rowSpan += cellBelow.rowSpan;

    targetRow.cells.removeAt(cellBelowIndex);

    widget.document.updateContent();
  }

  void _decreaseRowspan() {
    if (_clickedCell == null) return;
    final cell = _clickedCell!;
    if (cell.rowSpan <= 1) return;

    final position = _findCellPosition(cell);
    if (position == null) return;

    final rowIdx = position.$1;
    final colIdx = position.$2;

    // BUG FIX: the new cell should be inserted in the LAST row covered by the rowspan
    // (rowIdx + cell.rowSpan - 1), not always in rowIdx + 1.
    final targetRowIdx = rowIdx + cell.rowSpan - 1;

    cell.rowSpan--;

    if (targetRowIdx < widget.node.rows.length) {
      final targetRow = widget.node.rows[targetRowIdx];
      final logicalCol = _logicalColOf(rowIdx, colIdx);

      int logicalC = 0;
      int insertIndex = targetRow.cells.length;

      for (int c = 0; c < targetRow.cells.length; c++) {
        if (logicalC >= logicalCol) {
          insertIndex = c;
          break;
        }
        logicalC += targetRow.cells[c].colSpan;
      }

      final newCell = FluentCell();
      targetRow.cells.insert(insertIndex, newCell);
    }

    widget.document.updateContent();
  }

  void _moveCellContent(FluentCell sourceCell, FluentCell targetCell) {
    // Move all children from source to target, preserving styles
    if (targetCell.children.isEmpty) {
      // If target is empty, just move everything
      targetCell.children.addAll(sourceCell.children);
    } else {
      // If target has content, append the source content
      // Try to append to the last paragraph if it exists
      final lastChild = targetCell.children.last;
      if (lastChild is Paragraph && sourceCell.children.isNotEmpty) {
        final firstSourceChild = sourceCell.children.first;
        if (firstSourceChild is Paragraph) {
          // Append fragments from source paragraph to target paragraph
          lastChild.fragments.addAll(firstSourceChild.fragments);
          // Add remaining children from source
          if (sourceCell.children.length > 1) {
            targetCell.children.addAll(sourceCell.children.sublist(1));
          }
        } else {
          // Source doesn't start with paragraph, just add everything
          targetCell.children.addAll(sourceCell.children);
        }
      } else {
        // Target doesn't end with paragraph, just add everything
        targetCell.children.addAll(sourceCell.children);
      }
    }
    sourceCell.children.clear();

    // Clean up all paragraphs in the target cell (removes empty fragments
    // created during the move and merges adjacent fragments with identical styles)
    for (final child in targetCell.children) {
      if (child is Paragraph) {
        pruneEmptyFragments(child);
        _mergeAdjacentFragments(child);
      }
    }
  }

  bool _sameFragmentStyle(Fragment a, Fragment b) {
    final aStyles = (a.styles ?? []).toSet();
    final bStyles = (b.styles ?? []).toSet();
    if (aStyles != bStyles) return false;
    if (a.fontFamily != b.fontFamily) return false;
    if (a.fontSize != b.fontSize) return false;
    if (a.color != b.color) return false;
    if (a.highlightColor != b.highlightColor) return false;
    return true;
  }

  void _mergeAdjacentFragments(Paragraph paragraph) {
    if (paragraph.fragments.length < 2) return;
    final merged = <FNode>[];
    Fragment? current;
    for (final node in paragraph.fragments) {
      final frag = node is Fragment ? node : null;
      if (frag == null || frag is InlineContainerNode) {
        if (current != null) {
          merged.add(current);
          current = null;
        }
        merged.add(node);
        continue;
      }
      if (current == null) {
        current = frag;
      } else if (_sameFragmentStyle(current, frag)) {
        // Merge by concatenating text; the current fragment absorbs frag
        current.text += frag.text;
        // Do NOT add frag to merged list - it's absorbed into current
      } else {
        merged.add(current);
        current = frag;
      }
    }
    if (current != null) merged.add(current);
    paragraph.fragments.clear();
    paragraph.fragments.addAll(merged);
  }
}

// ─── Wrapper that notifies after each layout ────────────────────────────────────
class _NotifyingTableRenderer extends StatefulWidget {
  const _NotifyingTableRenderer({
    required this.tableKey,
    required this.node,
    required this.document,
    required this.colWidths,
    required this.availableWidth,
    required this.onLayout,
  });

  final GlobalKey tableKey;
  final FluentTable node;
  final FluentDocument document;
  final List<double> colWidths;
  final double availableWidth;
  final VoidCallback onLayout;

  @override
  State<_NotifyingTableRenderer> createState() => _NotifyingTableRendererState();
}

class _NotifyingTableRendererState extends State<_NotifyingTableRenderer> {
  @override
  void didUpdateWidget(_NotifyingTableRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLayout());
  }

  @override
  Widget build(BuildContext context) {
    return FluentTableWidgetRenderer(
      key: widget.tableKey,
      node: widget.node,
      document: widget.document,
      colWidths: widget.colWidths,
      availableWidth: widget.availableWidth,
    );
  }
}

// ParentData per le celle nella tabella
class FluentTableCellParentData extends ContainerBoxParentData<RenderBox> {
  int row = 0;
  int col = 0;
  int colSpan = 1;
  int rowSpan = 1;
  double width = 0;
  double height = 0;
}

class FluentTableWidgetRenderer extends MultiChildRenderObjectWidget {
  final FluentTable node;
  final List<double> colWidths;
  final double availableWidth;
  
  FluentTableWidgetRenderer({
    super.key,
    required this.node,
    required FluentDocument document,
    required this.colWidths,
    required this.availableWidth,
  }) : super(children: _flattenCells(node, document));

  // Extracts all cells into a flat list, adding position info
  static List<Widget> _flattenCells(FluentTable node, FluentDocument document) {
    final List<Widget> cells = [];
    for (int r = 0; r < node.rows.length; r++) {
      final row = node.rows[r];
      for (int c = 0; c < row.cells.length; c++) {
        final cell = row.cells[c];
        cells.add(_CellPositioned(
          key: ValueKey('${cell.id}_${cell.colSpan}_${cell.rowSpan}'),
          row: r,
          col: c,
          colSpan: cell.colSpan,
          rowSpan: cell.rowSpan,
          child: buildFNodeWidget(cell, document),
        ));
      }
    }
    return cells;
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderFluentTable(node: node, colWidths: colWidths);
  }

  @override
  void updateRenderObject(BuildContext context, covariant RenderFluentTable renderObject) {
    renderObject.node = node;
    renderObject.colWidths = colWidths;
    renderObject.markNeedsLayout();
  }
}

// Widget that carries position info to the render object
class _CellPositioned extends SingleChildRenderObjectWidget {
  final int row;
  final int col;
  final int colSpan;
  final int rowSpan;

  const _CellPositioned({
    super.key,
    required this.row,
    required this.col,
    required this.colSpan,
    required this.rowSpan,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCellPositioned(
      row: row, col: col, colSpan: colSpan, rowSpan: rowSpan,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderCellPositioned renderObject) {
    if (renderObject.row != row || 
        renderObject.col != col || 
        renderObject.colSpan != colSpan || 
        renderObject.rowSpan != rowSpan) {
      renderObject
        ..row = row
        ..col = col
        ..colSpan = colSpan
        ..rowSpan = rowSpan;
      renderObject.markNeedsLayout();
    }
  }
}

class _RenderCellPositioned extends RenderProxyBox {
  int row;
  int col;
  int colSpan;
  int rowSpan;

  _RenderCellPositioned({
    required this.row,
    required this.col,
    required this.colSpan,
    required this.rowSpan,
  });
}

class RenderFluentTable extends RenderFluentNode
    with ContainerRenderObjectMixin<RenderBox, FluentTableCellParentData>,
         RenderBoxContainerDefaultsMixin<RenderBox, FluentTableCellParentData> {
  
  static const double minCellWidth = 20.0;
  static const double minCellHeight = 20.0;
  static const double borderWidth = 1.0;

  List<double> _colWidths;
  List<double> _computedRowHeights = [];

  /// Row heights calculated in the last layout (in logical pixels).
  List<double> get computedRowHeights => _computedRowHeights;

  RenderFluentTable({required FluentTable node, required List<double> colWidths})
      : _colWidths = colWidths,
        super(node: node);

  set colWidths(List<double> value) {
    _colWidths = value;
    markNeedsLayout();
  }

  @override
  FluentTable get node => super.node as FluentTable;
  
  @override
  set node(covariant FluentTable value) {
    super.node = value;
    markNeedsLayout();
  }
  
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! FluentTableCellParentData) {
      child.parentData = FluentTableCellParentData();
    }
  }
  
  @override
  void performLayout() {
    // ── Build occupancy grid from data model ─────────────
    //
    // The data model may contain "orphan" cells in slots already covered by a
    // span (residue from previous operations). The occupancy grid is
    // the only source of truth: determines which cell occupies each logical slot
    // (row, logical-column) and ignores orphan cells during layout and
    // paint. This solves the problem at the root without requiring that the
    // data model is always perfectly canonical.

    final int numRows = node.rows.length;

    // First pass: calculate numCols respecting the occupancy grid.
    int numCols = 0;
    {
      final List<List<bool>> occ = List.generate(numRows, (_) => []);
      for (int r = 0; r < numRows; r++) {
        int logCol = 0;
        for (final cell in node.rows[r].cells) {
          while (logCol < occ[r].length && occ[r][logCol]) {
            logCol++;
          }
          final endCol = logCol + cell.colSpan;
          final endRow = math.min(r + cell.rowSpan, numRows);
          for (int rr = r; rr < endRow; rr++) {
            while (occ[rr].length < endCol) {
              occ[rr].add(false);
            }
            for (int cc = logCol; cc < endCol; cc++) {
              occ[rr][cc] = true;
            }
          }
          if (endCol > numCols) numCols = endCol;
          logCol = endCol;
        }
      }
    }

    if (numCols == 0 || numRows == 0) {
      size = constraints.constrain(Size.zero);
      return;
    }

    // ── Larghezze colonne ─────────────────────────────────────────────────
    List<double> colWidths;
    if (_colWidths.length == numCols) {
      colWidths = List.from(_colWidths);
      final total = colWidths.fold(0.0, (s, w) => s + w);
      if (total > constraints.maxWidth && constraints.maxWidth > 0) {
        final scale = constraints.maxWidth / total;
        colWidths = colWidths.map((w) => math.max(w * scale, minCellWidth)).toList();
      }
    } else {
      colWidths = List.filled(numCols, math.max(constraints.maxWidth / numCols, minCellWidth));
    }

    // ── Final grid: (r, logCol) → (physCol, cell) ────────────────
    //
    // physCol = physical index of the cell in its row (to match it to the
    // corresponding render child). Only origin cells are registered;
    // slots covered by others' spans remain null.
    final grid = List.generate(
      numRows, (_) => List<(int, FluentCell)?>.filled(numCols, null),
    );
    final occupied = List.generate(numRows, (_) => List.filled(numCols, false));

    for (int r = 0; r < numRows; r++) {
      int logCol = 0;
      final cells = node.rows[r].cells;
      for (int c = 0; c < cells.length; c++) {
        final cell = cells[c];
        while (logCol < numCols && occupied[r][logCol]) {
          logCol++;
        }
        if (logCol >= numCols) break; // orphan cell: no slot available

        final endCol = math.min(logCol + cell.colSpan, numCols);
        final endRow = math.min(r + cell.rowSpan, numRows);
        grid[r][logCol] = (c, cell);
        for (int rr = r; rr < endRow; rr++) {
          for (int cc = logCol; cc < endCol; cc++) {
            occupied[rr][cc] = true;
          }
        }
        logCol = endCol;
      }
    }

    // ── Map render children: (rowIdx, physColIdx) → RenderBox ──────────
    //
    // Render children arrive in the order of _flattenCells (row×physical col).
    // First copy row/col from _RenderCellPositioned into parentData.
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData as FluentTableCellParentData;
      if (child is _RenderCellPositioned) {
        pd.row = child.row;
        pd.col = child.col;
        pd.colSpan = child.colSpan;
        pd.rowSpan = child.rowSpan;
      }
      child = pd.nextSibling;
    }

    final Map<(int, int), RenderBox> childMap = {};
    child = firstChild;
    while (child != null) {
      final pd = child.parentData as FluentTableCellParentData;
      childMap[(pd.row, pd.col)] = child;
      child = pd.nextSibling;
    }

    // ── First pass: measure heights from content ────────────────────────
    final List<double> rowHeights = node.rows
        .map((r) => r.rowHeight ?? minCellHeight.toDouble())
        .toList();

    for (int r = 0; r < numRows; r++) {
      for (int logCol = 0; logCol < numCols; logCol++) {
        final entry = grid[r][logCol];
        if (entry == null) continue;
        final (physCol, cell) = entry;
        final rc = childMap[(r, physCol)];
        if (rc == null) continue;

        double cellWidth = 0;
        for (int c = logCol; c < math.min(logCol + cell.colSpan, numCols); c++) {
          cellWidth += colWidths[c];
        }
        rc.layout(
          BoxConstraints(minWidth: cellWidth, maxWidth: cellWidth, minHeight: minCellHeight),
          parentUsesSize: true,
        );
        final heightPerRow = rc.size.height / cell.rowSpan;
        for (int rr = r; rr < math.min(r + cell.rowSpan, numRows); rr++) {
          rowHeights[rr] = math.max(rowHeights[rr], heightPerRow);
        }
      }
    }

    // ── Offsets ───────────────────────────────────────────────────────────
    final List<double> rowOffsets = List.filled(numRows, 0);
    double ry = 0;
    for (int r = 0; r < numRows; r++) { rowOffsets[r] = ry; ry += rowHeights[r]; }

    final List<double> colOffsets = List.filled(numCols, 0);
    double cx = 0;
    for (int c = 0; c < numCols; c++) { colOffsets[c] = cx; cx += colWidths[c]; }

    // ── Second pass: position and final relayout ──────────────────────
    child = firstChild;
    while (child != null) {
      final pd = child.parentData as FluentTableCellParentData;
      final r = pd.row;
      final physCol = pd.col;

      // Find the logical column of this cell in the grid
      int? logCol;
      for (int lc = 0; lc < numCols; lc++) {
        final entry = grid[r][lc];
        if (entry != null && entry.$1 == physCol) { logCol = lc; break; }
      }

      if (logCol == null) {
        // Orphan cell: hide it completely outside the viewport
        pd.offset = const Offset(-10000, -10000);
        pd.width = 0;
        pd.height = 0;
        child.layout(const BoxConstraints(maxWidth: 0, maxHeight: 0), parentUsesSize: true);
      } else {
        final cell = grid[r][logCol]!.$2;
        double cellWidth = 0;
        for (int c = logCol; c < math.min(logCol + cell.colSpan, numCols); c++) {
          cellWidth += colWidths[c];
        }
        double cellHeight = 0;
        for (int rr = r; rr < math.min(r + cell.rowSpan, numRows); rr++) {
          cellHeight += rowHeights[rr];
        }
        pd.offset = Offset(colOffsets[logCol], rowOffsets[r]);
        pd.width = cellWidth;
        pd.height = cellHeight;
        child.layout(
          BoxConstraints(minWidth: cellWidth, maxWidth: cellWidth, minHeight: cellHeight),
          parentUsesSize: true,
        );
      }

      child = pd.nextSibling;
    }

    _computedRowHeights = List.from(rowHeights);
    size = constraints.constrain(Size(cx, ry));
  }
  
  @override
  void paint(PaintingContext context, Offset offset) {
    // Draw cells (before outer border)
    defaultPaint(context, offset);

    // Draw grid lines
    _drawGridLines(context, offset);

    // Draw outer border (above cells)
    final borderPaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    context.canvas.drawRect(offset & size, borderPaint);
    
  }
  
  void _drawGridLines(PaintingContext context, Offset offset) {
    final borderPaint = Paint()
      ..color = const Color(0xFFCCCCCC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw only non-orphan cells (offset != -10000).
    // Orphan cells were hidden by performLayout and should not be drawn.
    RenderBox? child = firstChild;
    while (child != null) {
      final parentData = child.parentData as FluentTableCellParentData;
      if (parentData.offset.dx > -9000) {
        final rect = Rect.fromLTWH(
          offset.dx + parentData.offset.dx,
          offset.dy + parentData.offset.dy,
          parentData.width,
          parentData.height,
        );
        context.canvas.drawRect(rect, borderPaint);
      }
      child = parentData.nextSibling;
    }
  }
  
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}