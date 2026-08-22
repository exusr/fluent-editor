import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';
import 'package:flutter/foundation.dart';

/// Represents a change to the document at the node level.
/// Deltas are much smaller than full document snapshots because they
/// store only the affected nodes, not the entire tree.
sealed class DocumentDelta {
  final String description;
  final DateTime timestamp;

  const DocumentDelta({
    required this.description,
    required this.timestamp,
  });

  /// Apply this delta (redo). Replaces affected nodes with their
  /// post-mutation state and restores the post-mutation cursor.
  void apply(FluentDocument document);

  /// Revert this delta (undo). Replaces affected nodes with their
  /// pre-mutation state and restores the pre-mutation cursor.
  void revert(FluentDocument document);
}

/// Cursor / selection state captured at the time of the delta.
class CursorSnapshot {
  final String anchorId;
  final int anchorOffset;
  final String? focusId;
  final int? focusOffset;

  const CursorSnapshot({
    required this.anchorId,
    required this.anchorOffset,
    this.focusId,
    this.focusOffset,
  });

  factory CursorSnapshot.fromDocument(FluentDocument document) {
    final cursor = document.cursor;
    return CursorSnapshot(
      anchorId: cursor.anchorId,
      anchorOffset: cursor.anchorOffset,
      focusId: cursor.isCollapsed ? null : cursor.focusId,
      focusOffset: cursor.isCollapsed ? null : cursor.focusOffset,
    );
  }

  void restore(FluentDocument document) {
    document.cursor.moveTo(anchorId, anchorOffset);
    if (focusId != null) {
      document.cursor.focusTo(focusId!, focusOffset!);
    }
  }
}

/// A single changed node: old JSON → new JSON at a specific index.
class NodeChange {
  final int index;
  final Map<String, dynamic> oldJson;
  final Map<String, dynamic> newJson;

  const NodeChange({
    required this.index,
    required this.oldJson,
    required this.newJson,
  });
}

/// Replaces one or more top-level nodes. This covers 95% of editor
/// operations (typing, formatting, delete, enter, etc.).
class NodeReplaceDelta extends DocumentDelta {
  final List<NodeChange> changes;
  final CursorSnapshot oldCursor;
  final CursorSnapshot newCursor;

  const NodeReplaceDelta({
    required super.description,
    required super.timestamp,
    required this.changes,
    required this.oldCursor,
    required this.newCursor,
  });

  @override
  void apply(FluentDocument document) {
    _replaceNodes(document, changes.map((c) => (c.index, c.newJson)));
    newCursor.restore(document);
  }

  @override
  void revert(FluentDocument document) {
    _replaceNodes(document, changes.map((c) => (c.index, c.oldJson)));
    oldCursor.restore(document);
  }

  void _replaceNodes(
    FluentDocument document,
    Iterable<(int, Map<String, dynamic>)> replacements,
  ) {
    // Build a map of index → target JSON for all changed indices.
    final changeMap = <int, Map<String, dynamic>>{};
    for (final (i, json) in replacements) {
      changeMap[i] = json;
    }

    // Rebuild the full node list: for each index, use the target JSON
    // if there's a change, keep the existing node if unchanged, or
    // skip if the target JSON is empty (node deleted).
    final nodes = document.content.nodes;
    final maxIndex = changeMap.keys.fold(nodes.length - 1, (a, b) => a > b ? a : b);

    final newNodes = <FNode>[];
    for (int i = 0; i <= maxIndex; i++) {
      final json = changeMap[i];
      if (json != null) {
        if (json.isNotEmpty) {
          newNodes.add(_deserializeNode(json, document.registry));
        }
        // Empty JSON ({}) → node doesn't exist in target state
      } else if (i < nodes.length) {
        // No change at this index — keep existing node
        newNodes.add(nodes[i]);
      }
    }

    document.content.nodes
      ..clear()
      ..addAll(newNodes);
    document.invalidateNodeIndex();
  }
}

/// Inserts a new top-level node at a given index.
class NodeInsertDelta extends DocumentDelta {
  final int index;
  final Map<String, dynamic> nodeJson;
  final CursorSnapshot oldCursor;
  final CursorSnapshot newCursor;

  const NodeInsertDelta({
    required super.description,
    required super.timestamp,
    required this.index,
    required this.nodeJson,
    required this.oldCursor,
    required this.newCursor,
  });

  @override
  void apply(FluentDocument document) {
    if (index < 0 || index > document.content.nodes.length) {
      debugPrint('[UNDO_WARN] NodeInsertDelta.apply index $index out of bounds');
      return;
    }
    document.content.nodes.insert(index, _deserializeNode(nodeJson, document.registry));
    document.invalidateNodeIndex();
    newCursor.restore(document);
  }

  @override
  void revert(FluentDocument document) {
    if (index < 0 || index >= document.content.nodes.length) {
      debugPrint('[UNDO_WARN] NodeInsertDelta.revert index $index out of bounds');
      return;
    }
    document.content.nodes.removeAt(index);
    document.invalidateNodeIndex();
    oldCursor.restore(document);
  }
}

/// Deletes a top-level node at a given index.
class NodeDeleteDelta extends DocumentDelta {
  final int index;
  final Map<String, dynamic> deletedNodeJson;
  final CursorSnapshot oldCursor;
  final CursorSnapshot newCursor;

  const NodeDeleteDelta({
    required super.description,
    required super.timestamp,
    required this.index,
    required this.deletedNodeJson,
    required this.oldCursor,
    required this.newCursor,
  });

  @override
  void apply(FluentDocument document) {
    if (index < 0 || index >= document.content.nodes.length) {
      debugPrint('[UNDO_WARN] NodeDeleteDelta.apply index $index out of bounds');
      return;
    }
    document.content.nodes.removeAt(index);
    document.invalidateNodeIndex();
    newCursor.restore(document);
  }

  @override
  void revert(FluentDocument document) {
    if (index < 0 || index > document.content.nodes.length) {
      debugPrint('[UNDO_WARN] NodeDeleteDelta.revert index $index out of bounds');
      return;
    }
    document.content.nodes.insert(index, _deserializeNode(deletedNodeJson, document.registry));
    document.invalidateNodeIndex();
    oldCursor.restore(document);
  }
}

/// Helper: deserialize a single top-level node from JSON.
/// Delegates to FNodeJsonConverter to avoid duplicating the type switch.
FNode _deserializeNode(Map<String, dynamic> json, [FluentPluginRegistry? registry]) {
  FNodeJsonConverter.activeRegistry = registry;
  try {
    return const FNodeJsonConverter().fromJson(json);
  } catch (e) {
    debugPrint('[UNDO_WARN] Failed to deserialize node ($e), returning empty paragraph');
    return Paragraph();
  } finally {
    FNodeJsonConverter.activeRegistry = null;
  }
}
