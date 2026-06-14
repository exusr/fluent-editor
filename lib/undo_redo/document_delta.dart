import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';

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
    // Sort by index descending so earlier indices are not shifted
    // by later replacements.
    final sorted = replacements.toList()
      ..sort((a, b) => b.$1.compareTo(a.$1));

    for (final (index, json) in sorted) {
      if (index < 0 || index >= document.content.nodes.length) {
        // Defensive: skip out-of-bound indices that can occur when
        // the document structure changed between capture and undo.
        continue;
      }
      final oldNode = document.content.nodes[index];
      final newNode = _deserializeNode(json);
      // Preserve the old id so render objects / keys stay stable
      newNode.id = oldNode.id;
      document.content.nodes[index] = newNode;
    }
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
      print('[UNDO_WARN] NodeInsertDelta.apply index $index out of bounds');
      return;
    }
    document.content.nodes.insert(index, _deserializeNode(nodeJson));
    document.invalidateNodeIndex();
    newCursor.restore(document);
  }

  @override
  void revert(FluentDocument document) {
    if (index < 0 || index >= document.content.nodes.length) {
      print('[UNDO_WARN] NodeInsertDelta.revert index $index out of bounds');
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
      print('[UNDO_WARN] NodeDeleteDelta.apply index $index out of bounds');
      return;
    }
    document.content.nodes.removeAt(index);
    document.invalidateNodeIndex();
    newCursor.restore(document);
  }

  @override
  void revert(FluentDocument document) {
    if (index < 0 || index > document.content.nodes.length) {
      print('[UNDO_WARN] NodeDeleteDelta.revert index $index out of bounds');
      return;
    }
    document.content.nodes.insert(index, _deserializeNode(deletedNodeJson));
    document.invalidateNodeIndex();
    oldCursor.restore(document);
  }
}

/// Helper: deserialize a single top-level node from JSON.
FNode _deserializeNode(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  switch (type) {
    case 'paragraph':
      return Paragraph.fromJson(json);
    case 'link':
      return Link.fromJson(json);
    case 'list':
      return FluentList.fromJson(json);
    case 'listItem':
      return ListItem.fromJson(json);
    case 'row':
      return FluentRow.fromJson(json);
    case 'cell':
      return FluentCell.fromJson(json);
    case 'table':
      return FluentTable.fromJson(json);
    case 'image':
      return FluentImage.fromJson(json);
    case 'hr':
      return HorizontalRule.fromJson(json);
    case 'fragment':
      return Fragment.fromJson(json);
    default:
      // Defensive: return an empty paragraph instead of crashing.
      // This can happen when a delta captures an empty map or unknown type.
      print('[UNDO_WARN] Unknown node type in delta: $type, returning empty paragraph');
      return Paragraph();
  }
}
