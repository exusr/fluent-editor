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
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

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

  late final NavigationResult result;
  late final bool isVertical;

  if (key == LogicalKeyboardKey.arrowLeft) {
    result = ctrl ? moveWordLeft(root, current) : moveLeft(root, current);
    isVertical = false;
  } else if (key == LogicalKeyboardKey.arrowRight) {
    result = ctrl ? moveWordRight(root, current) : moveRight(root, current);
    isVertical = false;
  } else if (key == LogicalKeyboardKey.arrowUp) {
    final pref = _adjustPreferredXForBlockImage(root, current, cursor.preferredX);
    result = moveUp(root, current, pref,
        document.resolveCaretX, document.resolveCaretY);
    isVertical = true;
  } else if (key == LogicalKeyboardKey.arrowDown) {
    final pref = _adjustPreferredXForBlockImage(root, current, cursor.preferredX);
    result = moveDown(root, current, pref,
        document.resolveCaretX, document.resolveCaretY);
    isVertical = true;
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

  // Keep SelectionManager always in sync with cursor anchor/focus
  _syncSelectionManager(document);

  document.updateContent();
  return true;
}

/// If [current] is a caret stop of a block-level FluentImage (direct child
/// of Root/ListItem/FluentCell, not inside a Paragraph/Link), forces
/// preferredX to `double.infinity` when not already fixed. So shift+down/up
/// from the image lands at the end of the first line of the next paragraph, making
/// the selection extension visible on the text (the first line is
/// highlighted instead of being "selected with zero length" at offset 0).
double _adjustPreferredXForBlockImage(
  Root root,
  CaretStop current,
  double preferredX,
) {
  if (preferredX >= 0.0) return preferredX;
  final node = findById(root, current.fragmentId);
  if (node == null) return preferredX;
  if (node is! FluentImage && node is! HorizontalRule) return preferredX;
  // Block-level if the parent is NOT a Paragraph (Link is Paragraph subclass).
  final parent = findParent(root, node);
  if (parent is Paragraph) return preferredX;
  return double.infinity;
}

/// Synchronizes SelectionManager with the current cursor state.
/// Called after every movement, with or without shift.
void _syncSelectionManager(FluentDocument document) {
  final cursor = document.cursor;

  if (cursor.isCollapsed) {
    // No selection: collapse
    document.selectionManager.collapse();
    return;
  }

  final anchorNodeId = document.findLogicalContainerId(cursor.anchorId);
  final focusNodeId  = document.findLogicalContainerId(cursor.focusId);

  if (anchorNodeId == null || focusNodeId == null) {
    document.selectionManager.clear();
    return;
  }

  // Set fixed anchor, then update focus – batched so we notify only once.
  document.selectionManager.batchUpdate(() {
    document.selectionManager.startSelection(
      anchorNodeId,
      cursor.anchorId,
      cursor.anchorOffset,
    );
    document.selectionManager.updateFocus(
      focusNodeId,
      cursor.focusId,
      cursor.focusOffset,
    );
  });

  // Directly push the new selection range into the affected render
  // objects and force an immediate repaint. During key-hold Flutter
  // batches widget rebuilds, so the render objects still hold stale
  // values even though the underlying state changed. By updating
  // them directly we bypass the widget layer and the highlight
  // becomes visible frame-by-frame.
  final sm = document.selectionManager;
  final registry = document.paragraphRegistry;
  for (final entry in registry.renders.entries) {
    final nodeId = entry.key;
    final render = entry.value;
    final range = sm.getRangeForNode(nodeId);
    if (range != null) {
      render.setSelectionRange(
        range.startFrag, range.startOff,
        range.endFrag, range.endOff,
      );
    } else {
      render.setSelectionRange(null, null, null, null);
    }
    render.markNeedsPaint();
  }
  SchedulerBinding.instance.ensureVisualUpdate();
}