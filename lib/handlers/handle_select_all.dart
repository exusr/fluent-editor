import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';

bool handleSelectAll(FluentDocument document) {
  final root = document.content;
  final cursor = document.cursor;
  
  if (root.nodes.isEmpty) return false;
  
  // Build all stops in the document (the "rail" for cursor navigation)
  final stops = buildAllStops(root);
  if (stops.isEmpty) return false;
  
  // Select from first to last stop
  final firstStop = stops.first;
  final lastStop = stops.last;
  
  cursor.moveTo(firstStop.fragmentId, firstStop.offset);
  cursor.focusTo(lastStop.fragmentId, lastStop.offset);
  
  // Sync SelectionManager to show visual selection
  _syncSelectionManager(document);
  
  document.updateContent();
  return true;
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

  // Set fixed anchor, then update focus
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