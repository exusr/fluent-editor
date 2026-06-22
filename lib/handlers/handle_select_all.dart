import 'package:fluent_editor/fluent_document.dart';

bool handleSelectAll(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;
  
  if (root.nodes.isEmpty) return false;
  
  final stops = document.caretStops;
  if (stops.isEmpty) return false;

  final firstStop = stops.first;
  final lastStop = stops.last;

  cursor.moveTo(firstStop.fragmentId, firstStop.offset);
  cursor.focusTo(lastStop.fragmentId, lastStop.offset);

  _syncSelectionManager(document);

  document.cursorOnlyUpdate();
  return true;
}

/// Synchronizes SelectionManager with the current cursor state.
/// Called after every movement, with or without shift.
void _syncSelectionManager(FluentDocument document) {
  final cursor = document.cursor;

  if (cursor.isCollapsed) {
    document.selectionManager.collapse();
    return;
  }

  final anchorNodeId = document.findLogicalContainerId(cursor.anchorId);
  final focusNodeId  = document.findLogicalContainerId(cursor.focusId);

  if (anchorNodeId == null || focusNodeId == null) {
    document.selectionManager.clear();
    return;
  }

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
}