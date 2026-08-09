import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/selection_manager.dart';
import 'package:flutter/services.dart';

bool executeHandleArrowKey(
  LogicalKeyboardKey key,
  FluentDocument document, {
  bool ctrl = false,
  bool shift = false,
}) {
  final cursor = document.cursor;
  final current = shift
      ? CaretStop(cursor.focusId, cursor.focusOffset)
      : CaretStop(cursor.anchorId, cursor.anchorOffset);
  final root = document.content;

  final stops = document.caretStops;

  late final NavigationResult result;
  late final bool isVertical;

  if (!shift && !cursor.isCollapsed) {
    final anchorIdx = findStopIndex(stops, cursor.anchorId, cursor.anchorOffset);
    final focusIdx = findStopIndex(stops, cursor.focusId, cursor.focusOffset);

    if (anchorIdx >= 0 && focusIdx >= 0) {
      final start = anchorIdx <= focusIdx
          ? CaretStop(cursor.anchorId, cursor.anchorOffset)
          : CaretStop(cursor.focusId, cursor.focusOffset);
      final end = anchorIdx <= focusIdx
          ? CaretStop(cursor.focusId, cursor.focusOffset)
          : CaretStop(cursor.anchorId, cursor.anchorOffset);

      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowUp) {
        cursor.batchUpdate(() {
          cursor.moveTo(start.fragmentId, start.offset);
        });
        document.syncPendingFontWithCursor();
        document.selectionManager.collapse();
        _syncSelectionManager(document);
        document.cursorOnlyUpdate();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowDown) {
        cursor.batchUpdate(() {
          cursor.moveTo(end.fragmentId, end.offset);
        });
        document.syncPendingFontWithCursor();
        document.selectionManager.collapse();
        _syncSelectionManager(document);
        document.cursorOnlyUpdate();
        return true;
      }
    }
  }

  if (key == LogicalKeyboardKey.arrowLeft) {
    result = ctrl
        ? moveWordLeft(root, current,
            stops: stops, cachedLines: document.logicalLines)
        : moveLeft(root, current, stops: stops);
    isVertical = false;
  } else if (key == LogicalKeyboardKey.arrowRight) {
    result = ctrl
        ? moveWordRight(root, current,
            stops: stops, cachedLines: document.logicalLines)
        : moveRight(root, current, stops: stops);
    isVertical = false;
  } else if (key == LogicalKeyboardKey.arrowUp ||
             key == LogicalKeyboardKey.arrowDown) {
    final currentNode = document.nodeById(current.fragmentId);
    final isBlockNode = currentNode is HorizontalRule || currentNode is FluentImage;

    if (isBlockNode) {
      final allStops = document.caretStops;
      final currentIdx = findStopIndex(allStops, current.fragmentId, current.offset);
      if (currentIdx >= 0) {
        if (key == LogicalKeyboardKey.arrowUp) {
          if (currentIdx > 0) {
            result = NavigationResult(position: allStops[currentIdx - 1], preferredX: -1.0);
          } else {
            result = NavigationResult.none;
          }
        } else { // arrowDown
          int nextIdx = currentIdx + 1;
          while (nextIdx < allStops.length &&
                 allStops[nextIdx].fragmentId == current.fragmentId) {
            nextIdx++;
          }
          if (nextIdx < allStops.length) {
            result = NavigationResult(position: allStops[nextIdx], preferredX: -1.0);
          } else {
            result = NavigationResult.none;
          }
        }
        isVertical = true;
      }
    } else {
      final currentContainerId = document.findLogicalContainerId(current.fragmentId);
      final containerOrder = document.containerOrder;
      final containerIdx = containerOrder.indexOf(currentContainerId ?? '');
      final candidateIds = <String>{};
      if (containerIdx >= 0) {
        candidateIds.add(containerOrder[containerIdx]);

        String? _nearestStructure(String? id) {
          if (id == null) return null;
          String? pid = id;
          while (pid != null) {
            final node = document.nodeById(pid);
            if (node is FluentTable || node is FluentList) return pid;
            pid = document.findParentCached(pid);
          }
          return null;
        }

        bool _isInsideStructure(String? containerId, String structureId) {
          if (containerId == null) return false;
          String? pid = containerId;
          while (pid != null) {
            if (pid == structureId) return true;
            pid = document.findParentCached(pid);
          }
          return false;
        }

        String? _cellFor(String? containerId) {
          if (containerId == null) return null;
          String? pid = containerId;
          while (pid != null) {
            final node = document.nodeById(pid);
            if (node is FluentCell) return pid;
            pid = document.findParentCached(pid);
          }
          return null;
        }

        final currentEnclosing = _nearestStructure(currentContainerId);
        if (currentEnclosing != null) {
          final enclosingNode = document.nodeById(currentEnclosing);
          if (enclosingNode is FluentTable) {
            final table = enclosingNode;
            final currentCellId = _cellFor(currentContainerId);
            if (currentCellId != null) {
              int rowIndex = -1;
              int logicalCol = -1;
              for (int r = 0; r < table.rows.length; r++) {
                final row = table.rows[r];
                int col = 0;
                for (int c = 0; c < row.cells.length; c++) {
                  if (row.cells[c].id == currentCellId) {
                    rowIndex = r;
                    logicalCol = col;
                    break;
                  }
                  col += row.cells[c].colSpan;
                }
                if (rowIndex >= 0) break;
              }
              if (rowIndex >= 0 && logicalCol >= 0) {
                for (final id in containerOrder) {
                  if (_isInsideStructure(id, currentCellId)) {
                    candidateIds.add(id);
                  }
                }
                if (rowIndex > 0) {
                  final aboveCellId = _findCellAtLogicalCol(
                    table.rows[rowIndex - 1], logicalCol);
                  if (aboveCellId != null) {
                    for (final id in containerOrder) {
                      if (_isInsideStructure(id, aboveCellId)) {
                        candidateIds.add(id);
                      }
                    }
                  }
                }
                if (rowIndex < table.rows.length - 1) {
                  final belowCellId = _findCellAtLogicalCol(
                    table.rows[rowIndex + 1], logicalCol);
                  if (belowCellId != null) {
                    for (final id in containerOrder) {
                      if (_isInsideStructure(id, belowCellId)) {
                        candidateIds.add(id);
                      }
                    }
                  }
                }
              }
            }
          } else if (enclosingNode is FluentList) {
            for (final id in containerOrder) {
              if (_isInsideStructure(id, currentEnclosing)) {
                candidateIds.add(id);
              }
            }
          }
          if (containerIdx > 0) {
            for (int i = containerIdx - 1; i >= 0; i--) {
              final id = containerOrder[i];
              if (!_isInsideStructure(id, currentEnclosing)) {
                candidateIds.add(id);
                break;
              }
            }
          }
          if (containerIdx < containerOrder.length - 1) {
            for (int i = containerIdx + 1; i < containerOrder.length; i++) {
              final id = containerOrder[i];
              if (!_isInsideStructure(id, currentEnclosing)) {
                candidateIds.add(id);
                break;
              }
            }
          }
        } else {
          if (containerIdx > 0) candidateIds.add(containerOrder[containerIdx - 1]);
          if (containerIdx < containerOrder.length - 1) {
            candidateIds.add(containerOrder[containerIdx + 1]);
          }
        }
      }
      final candidateStops = candidateIds.isNotEmpty
          ? candidateIds
              .expand<CaretStop>((id) => document.stopsByContainer[id] ?? [])
              .toList()
          : stops;
      final pref = _adjustPreferredXForBlockImage(document, current, cursor.preferredX);
      if (key == LogicalKeyboardKey.arrowUp) {
        result = moveUp(root, current, pref,
            document.resolveCaretX, document.resolveCaretY,
            stops: candidateStops, allStops: stops,
            parentResolver: document.findParentCached,
            containerResolver: document.findLogicalContainerId,
            topLevelIndexResolver: document.topLevelIndexOf);
      } else {
        result = moveDown(root, current, pref,
            document.resolveCaretX, document.resolveCaretY,
            stops: candidateStops, allStops: stops,
            parentResolver: document.findParentCached,
            containerResolver: document.findLogicalContainerId,
            topLevelIndexResolver: document.topLevelIndexOf);
      }
      isVertical = true;
    }
  } else {
    return false;
  }

  final newPos = result.position;
  if (newPos == null) return true;

  if (shift) {
    cursor.batchUpdate(() {
      cursor.focusTo(newPos.fragmentId, newPos.offset);
      cursor.preferredX = isVertical ? result.preferredX : -1.0;
    });
  } else {
    cursor.batchUpdate(() {
      cursor.moveTo(newPos.fragmentId, newPos.offset);
      if (isVertical) cursor.preferredX = result.preferredX;
    });
    document.syncPendingFontWithCursor();
  }

  _syncSelectionManager(document);

  document.cursorOnlyUpdate();

  return true;
}

/// If [current] is a caret stop of a block-level FluentImage (direct child
/// of Root/ListItem/FluentCell, not inside a Paragraph/Link), forces
/// preferredX to `double.infinity` when not already fixed. So shift+down/up
/// from the image lands at the end of the first line of the next paragraph, making
/// the selection extension visible on the text (the first line is
/// highlighted instead of being "selected with zero length" at offset 0).
double _adjustPreferredXForBlockImage(
  FluentDocument document,
  CaretStop current,
  double preferredX,
) {
  if (preferredX >= 0.0) return preferredX;
  final node = document.nodeById(current.fragmentId);
  if (node == null) return preferredX;
  if (node is! FluentImage && node is! HorizontalRule) return preferredX;
  final containerId = document.findLogicalContainerId(current.fragmentId);
  if (containerId == null) return preferredX;
  final container = document.nodeById(containerId);
  if (container is Paragraph) return preferredX;
  return double.infinity;
}

/// Tracks which visible nodes had a selection in the last sync pass,
/// keyed by the identity of the SelectionState. When the state object
/// changes (a new SelectionState was created) we know the ranges may
/// have changed; otherwise we can skip the entire sync.
SelectionState? _lastSyncState;

/// Cache of the last range pushed into each visible render object,
/// so we only call setSelectionRange when the range REALLY changed.
final Map<String, ({String? sFrag, int? sOff, String? eFrag, int? eOff})>
    _lastRenderRange = {};

/// Perf-specialized variant of [syncSelectionManager] (from handle_formats.dart)
/// with render-range caching. Only touches renders whose selection range actually
/// changed, reducing per-frame cost from O(visible) to O(changed).
void _syncSelectionManager(FluentDocument document) {
  final cursor = document.cursor;

  if (cursor.isCollapsed) {
    if (_lastSyncState != null) {
      document.selectionManager.collapse();
      _lastSyncState = null;
      _lastRenderRange.clear();
    }
    return;
  }

  final anchorNodeId = document.findLogicalContainerId(cursor.anchorId);
  final focusNodeId  = document.findLogicalContainerId(cursor.focusId);

  if (anchorNodeId == null || focusNodeId == null) {
    if (_lastSyncState != null) {
      document.selectionManager.clear();
      _lastSyncState = null;
      _lastRenderRange.clear();
    }
    return;
  }

  final sm = document.selectionManager;

  sm.batchUpdate(() {
    sm.startSelection(anchorNodeId, cursor.anchorId, cursor.anchorOffset);
    sm.updateFocus(focusNodeId, cursor.focusId, cursor.focusOffset);
  });

  _lastSyncState = sm.state;

  final registry = document.paragraphRegistry;
  final seenIds = <String>{};
  for (final entry in registry.visibleRenders) {
    final nodeId = entry.key;
    seenIds.add(nodeId);
    final render = entry.value;
    final range = sm.getRangeForNode(nodeId);

    final old = _lastRenderRange[nodeId];
    final new_ = range != null
        ? (sFrag: range.startFrag, sOff: range.startOff,
           eFrag: range.endFrag,   eOff: range.endOff)
        : (sFrag: null, sOff: null, eFrag: null, eOff: null);

    if (old != null &&
        old.sFrag == new_.sFrag && old.sOff == new_.sOff &&
        old.eFrag == new_.eFrag && old.eOff == new_.eOff) {
      continue;
    }
    _lastRenderRange[nodeId] = new_;

    if (range != null) {
      render.setSelectionRange(
        range.startFrag, range.startOff,
        range.endFrag, range.endOff,
      );
    } else {
      render.setSelectionRange(null, null, null, null);
    }
  }

  _lastRenderRange.removeWhere((id, _) => !seenIds.contains(id));
}

/// Finds the cell ID in [row] that occupies the given [logicalCol] position.
/// Accounts for colSpan: a cell with colSpan=3 occupies logical columns
/// col, col+1, col+2.
String? _findCellAtLogicalCol(FluentRow row, int logicalCol) {
  int col = 0;
  for (final cell in row.cells) {
    if (col <= logicalCol && logicalCol < col + cell.colSpan) {
      return cell.id;
    }
    col += cell.colSpan;
  }
  return null;
}