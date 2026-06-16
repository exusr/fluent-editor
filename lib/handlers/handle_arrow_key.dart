// handle_arrow_key.dart
//
// Management of directional arrow keys. Delegates all navigation logic
// to the pure `cursor_navigation.dart` module, and is limited to:
//  1. Reading the current position from Cursor
//  2. Invoking moveLeft/moveRight/moveUp/moveDown
//  3. Applying the result to Cursor
//
// For Up/Down, inject document.paragraphRegistry.resolveCaretX as
// CaretXResolver, so vertical navigation uses real x coordinates
// instead of the stop index.

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/selection_manager.dart';
import 'package:flutter/services.dart';

/// Profiling counters for the arrow-key hot path.
class _ArrowKeyProfile {
  static int callCount = 0;
  static int totalWordNavUs = 0;
  static int totalSyncSelUs = 0;
  static int totalCursorUpUs = 0;
  static int totalTimeUs = 0;
  static int maxWordNavUs = 0;
  static int maxSyncSelUs = 0;
  static int maxTotalUs = 0;

  static void _maybeReport() {
    print('[ARROW_PROFILE] calls=$callCount '
        'total=${totalTimeUs ~/ callCount}μs '
        'wordNav=${totalWordNavUs ~/ callCount}μs '
        'syncSel=${totalSyncSelUs ~/ callCount}μs '
        'cursorUp=${totalCursorUpUs ~/ callCount}μs '
        'maxTotal=${maxTotalUs}μs maxWordNav=${maxWordNavUs}μs maxSyncSel=${maxSyncSelUs}μs');
  }
}

bool executeHandleArrowKey(
  LogicalKeyboardKey key,
  FluentDocument document, {
  bool ctrl = false,
  bool shift = false,
}) {
  _ArrowKeyProfile.callCount++;
  final swTotal = Stopwatch()..start();

  final cursor = document.cursor;
  final current = shift
      ? CaretStop(cursor.focusId, cursor.focusOffset)
      : CaretStop(cursor.anchorId, cursor.anchorOffset);
  final root = document.content;

  // Measure caretStops getter (should be O(1) cached, but verify)
  final swStops = Stopwatch()..start();
  final stops = document.caretStops;
  swStops.stop();
  print('[ARROW_DETAIL] caretStops=${swStops.elapsedMicroseconds}μs len=${stops.length}');

  late final NavigationResult result;
  late final bool isVertical;

  // When there's an active selection and shift is not pressed, arrow keys
  // should collapse the selection to the appropriate edge rather than
  // moving from the anchor position.
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

  final swWord = Stopwatch()..start();
  if (key == LogicalKeyboardKey.arrowLeft) {
    final swMove = Stopwatch()..start();
    result = ctrl
        ? moveWordLeft(root, current,
            stops: stops, cachedLines: document.logicalLines)
        : moveLeft(root, current, stops: stops);
    swMove.stop();
    print('[ARROW_DETAIL] moveLeft=${swMove.elapsedMicroseconds}μs');
    isVertical = false;
  } else if (key == LogicalKeyboardKey.arrowRight) {
    final swMove = Stopwatch()..start();
    result = ctrl
        ? moveWordRight(root, current,
            stops: stops, cachedLines: document.logicalLines)
        : moveRight(root, current, stops: stops);
    swMove.stop();
    print('[ARROW_DETAIL] moveRight=${swMove.elapsedMicroseconds}μs');
    isVertical = false;
  } else if (key == LogicalKeyboardKey.arrowUp ||
             key == LogicalKeyboardKey.arrowDown) {
    // Check if cursor is on a block-level node (HR, Image).
    // These nodes don't have reliable Y coordinates, so use index-based navigation.
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
          // Skip all stops of the current block node
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
      // Vertical navigation: scan only the current container + neighbours
      // instead of every stop in the document. Reduces O(n_stops) → O(container).
      final swVert = Stopwatch()..start();
      final currentContainerId = document.findLogicalContainerId(current.fragmentId);
      final containerOrder = document.containerOrder;
      final containerIdx = containerOrder.indexOf(currentContainerId ?? '');
      final candidateIds = <String>{};
      if (containerIdx >= 0) {
        candidateIds.add(containerOrder[containerIdx]);

        // If inside a table or list, expand to include ALL containers in that
        // structure so Up/Down can cross rows/items.  The immediate
        // predecessor / successor in containerOrder are only added if they
        // are OUTSIDE the structure, otherwise the structural expansion
        // already covers them and they can point to the wrong column/row.
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
              int colIndex = -1;
              for (int r = 0; r < table.rows.length; r++) {
                final row = table.rows[r];
                for (int c = 0; c < row.cells.length; c++) {
                  if (row.cells[c].id == currentCellId) {
                    rowIndex = r;
                    colIndex = c;
                    break;
                  }
                }
                if (rowIndex >= 0) break;
              }
              // Current cell + cell above + cell below (same column only)
              if (rowIndex >= 0 && colIndex >= 0) {
                for (final id in containerOrder) {
                  if (_isInsideStructure(id, currentCellId)) {
                    candidateIds.add(id);
                  }
                }
                if (rowIndex > 0 && colIndex < table.rows[rowIndex - 1].cells.length) {
                  final aboveCellId = table.rows[rowIndex - 1].cells[colIndex].id;
                  for (final id in containerOrder) {
                    if (_isInsideStructure(id, aboveCellId)) {
                      candidateIds.add(id);
                    }
                  }
                }
                if (rowIndex < table.rows.length - 1 &&
                    colIndex < table.rows[rowIndex + 1].cells.length) {
                  final belowCellId = table.rows[rowIndex + 1].cells[colIndex].id;
                  for (final id in containerOrder) {
                    if (_isInsideStructure(id, belowCellId)) {
                      candidateIds.add(id);
                    }
                  }
                }
              }
            }
          } else if (enclosingNode is FluentList) {
            // Lists are 1-D: full structural expansion
            for (final id in containerOrder) {
              if (_isInsideStructure(id, currentEnclosing)) {
                candidateIds.add(id);
              }
            }
          }
          // Find first predecessor OUTSIDE the structure (exit upward)
          if (containerIdx > 0) {
            for (int i = containerIdx - 1; i >= 0; i--) {
              final id = containerOrder[i];
              if (!_isInsideStructure(id, currentEnclosing)) {
                candidateIds.add(id);
                break;
              }
            }
          }
          // Find first successor OUTSIDE the structure (exit downward)
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
          // Not inside a table/list: use immediate neighbours as before.
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
      final swMove = Stopwatch()..start();
      final pref = _adjustPreferredXForBlockImage(document, current, cursor.preferredX);
      if (key == LogicalKeyboardKey.arrowUp) {
        result = moveUp(root, current, pref,
            document.resolveCaretX, document.resolveCaretY, stops: candidateStops);
      } else {
        result = moveDown(root, current, pref,
            document.resolveCaretX, document.resolveCaretY, stops: candidateStops);
      }
      swMove.stop();
      swVert.stop();
      print('[ARROW_DETAIL] vertSetup=${swVert.elapsedMicroseconds}μs move=${swMove.elapsedMicroseconds}μs');
      isVertical = true;
    }
  } else {
    return false;
  }
  swWord.stop();
  _ArrowKeyProfile.totalWordNavUs += swWord.elapsedMicroseconds;
  if (swWord.elapsedMicroseconds > _ArrowKeyProfile.maxWordNavUs) {
    _ArrowKeyProfile.maxWordNavUs = swWord.elapsedMicroseconds;
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

  // Keep SelectionManager always in sync with cursor anchor/focus
  final swSync = Stopwatch()..start();
  _syncSelectionManager(document);
  swSync.stop();
  _ArrowKeyProfile.totalSyncSelUs += swSync.elapsedMicroseconds;
  if (swSync.elapsedMicroseconds > _ArrowKeyProfile.maxSyncSelUs) {
    _ArrowKeyProfile.maxSyncSelUs = swSync.elapsedMicroseconds;
  }

  // Arrow navigation never mutates content: use the cursor-only notification
  // so the cached caret-stop rail and node index survive across key presses.
  final swCursor = Stopwatch()..start();
  document.cursorOnlyUpdate();
  swCursor.stop();
  _ArrowKeyProfile.totalCursorUpUs += swCursor.elapsedMicroseconds;

  swTotal.stop();
  _ArrowKeyProfile.totalTimeUs += swTotal.elapsedMicroseconds;
  if (swTotal.elapsedMicroseconds > _ArrowKeyProfile.maxTotalUs) {
    _ArrowKeyProfile.maxTotalUs = swTotal.elapsedMicroseconds;
  }
  _ArrowKeyProfile._maybeReport();

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
  // Block-level if the logical container is NOT a Paragraph
  // (i.e. the container is the image itself, not a surrounding paragraph).
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

/// Synchronizes SelectionManager with the current cursor state.
/// Called after every movement, with or without shift.
///
/// OPTIMISATION: instead of touching every visible render on every key
/// press (O(visible) = ~20 ops/frame), we only touch renders whose
/// selection range actually changed. This reduces the per-frame cost
/// from O(visible) to O(changed), which is typically 1-2 paragraphs
/// during a word-by-word SHIFT+arrow hold.
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

  // Set fixed anchor, then update focus – batched so we notify only once.
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

    // Skip if the range is identical to what we pushed last time.
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

  // Clean up entries for nodes that scrolled out of view.
  _lastRenderRange.removeWhere((id, _) => !seenIds.contains(id));
}