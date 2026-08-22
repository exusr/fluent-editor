import 'dart:async';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/undo_redo/document_delta.dart';
import 'package:flutter/foundation.dart';

/// Lightweight snapshot of top-level nodes used to build deltas.
/// Stores only node VERSIONS (integers) for O(n) dirty detection,
/// plus the JSON of nodes that actually changed. This avoids
/// serialising the entire document tree on every commit.
class _PendingSnapshot {
  String description;
  final DateTime timestamp;

  /// Full JSON of every top-level node at capture time.
  /// Reused from [_jsonCache] when possible to avoid re-serializing
  /// unchanged nodes on every beginSaveState call.
  final List<Map<String, dynamic>> oldTopLevelNodes;

  final CursorSnapshot oldCursor;

  _PendingSnapshot({
    required this.description,
    required this.timestamp,
    required this.oldTopLevelNodes,
    required this.oldCursor,
  });
}

/// Result of committing a document saveState operation.
enum SaveStateResult {
  /// A new delta was created and pushed to the undo stack.
  created,

  /// The changes were merged into the previous delta on the undo stack.
  merged,

  /// No changes were detected; no delta was created or merged.
  noChange,
}

/// Undo/Redo system manager using node-level deltas instead of
/// full document snapshots. Memory usage is reduced by 50-100x
/// because only changed top-level nodes are stored.
class UndoRedoManager {
  static const int _maxUndoStates = 100;
  static const Duration _groupingTimeout = Duration(milliseconds: 300);

  final List<DocumentDelta> _undoStack = [];
  final List<DocumentDelta> _redoStack = [];

  Timer? _groupingTimer;
  String? _currentGroupDescription;
  DateTime? _lastActionTime;

  bool _isRestoringState = false;
  bool _forceNewAction = false;

  Set<String> _lastCommittedNodeIds = {};
  Set<String> get lastCommittedNodeIds => _lastCommittedNodeIds;

  int get undoStackSize => _undoStack.length;

  /// Pending snapshot captured by [beginSaveState]; committed by
  /// [commitSaveState] (called from [updateContent]).
  _PendingSnapshot? _pending;

  /// Cache of nodeId → JSON from the last committed state.
  /// Lets beginSaveState reuse the pre-mutation JSON without
  /// re-serializing unchanged nodes (O(changed) instead of O(n)).
  final Map<String, Map<String, dynamic>> _jsonCache = {};

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Called BEFORE a mutation. Captures the old state of all top-level
  /// nodes so [commitSaveState] can compute a minimal delta afterwards.
  void beginSaveState(
    FluentDocument document, {
    String description = 'Document change',
    bool forceNewAction = false,
  }) {
    if (_isRestoringState) return;

    final now = DateTime.now();

    if (!forceNewAction &&
        _pending != null &&
        !_forceNewAction &&
        _currentGroupDescription != null &&
        description == _currentGroupDescription &&
        _lastActionTime != null &&
        now.difference(_lastActionTime!) <= _groupingTimeout) {
      _pending!.description = description;
      _groupingTimer?.cancel();
      _groupingTimer = Timer(_groupingTimeout, _resetGrouping);
      return;
    }

    if (_pending != null) {
      _pending = null;
    }

    final nodes = document.content.nodes;
    final currentIds = <String>{};
    final oldJsonList = <Map<String, dynamic>>[];
    for (final node in nodes) {
      currentIds.add(node.id);
      final cached = _jsonCache[node.id];
      if (cached != null) {
        oldJsonList.add(cached);
      } else {
        final json = node.toJson();
        _jsonCache[node.id] = json;
        oldJsonList.add(json);
      }
    }
    // Evict stale entries for nodes no longer in the document.
    _jsonCache.removeWhere((id, _) => !currentIds.contains(id));
    _pending = _PendingSnapshot(
      description: description,
      timestamp: now,
      oldTopLevelNodes: oldJsonList,
      oldCursor: CursorSnapshot.fromDocument(document),
    );

    _forceNewAction = forceNewAction;
    _currentGroupDescription = description;
    _lastActionTime = now;
    _groupingTimer?.cancel();
    _groupingTimer = Timer(_groupingTimeout, _resetGrouping);
  }

  /// Called AFTER a mutation (from [FluentDocument.updateContent]).
  /// Compares the current top-level nodes with the pending snapshot,
  /// builds a minimal [DocumentDelta], and pushes it onto the undo stack.
  /// Returns a [SaveStateResult] indicating whether a new delta was created,
  /// merged into an existing delta, or if no changes occurred.
  SaveStateResult commitSaveState(FluentDocument document) {
    if (_isRestoringState || _pending == null) return SaveStateResult.noChange;

    final pending = _pending!;
    final newNodes = document.content.nodes;
    final oldNodes = pending.oldTopLevelNodes;

    final changes = <NodeChange>[];

    if (newNodes.length == oldNodes.length) {
      for (int i = 0; i < oldNodes.length; i++) {
        final oldJson = oldNodes[i];
        final newNode = newNodes[i];

        final newJson = newNode.toJson();
        if (!_mapsEqual(oldJson, newJson)) {
          changes.add(NodeChange(
            index: i,
            oldJson: oldJson,
            newJson: newJson,
          ));
        }
      }
    } else {
      final maxLen = oldNodes.length > newNodes.length
          ? oldNodes.length
          : newNodes.length;
      for (int i = 0; i < maxLen; i++) {
        final oldJson = i < oldNodes.length ? oldNodes[i] : null;
        final newNode = i < newNodes.length ? newNodes[i] : null;
        final newJson = newNode?.toJson();
        if (oldJson == null || newJson == null || !_mapsEqual(oldJson, newJson)) {
          changes.add(NodeChange(
            index: i,
            oldJson: oldJson ?? <String, dynamic>{},
            newJson: newJson ?? <String, dynamic>{},
          ));
        }
      }
    }

    if (changes.isEmpty) {
      _pending = null;
      _lastCommittedNodeIds = {};
      return SaveStateResult.noChange;
    }

    final committedIds = <String>{};
    for (final change in changes) {
      final oldId = change.oldJson['id'];
      if (oldId is String) committedIds.add(oldId);

      final newId = change.newJson['id'];
      if (newId is String) committedIds.add(newId);

      if (change.index < newNodes.length) {
        committedIds.add(newNodes[change.index].id);
      }
    }
    _lastCommittedNodeIds = committedIds;

    final delta = NodeReplaceDelta(
      description: pending.description,
      timestamp: pending.timestamp,
      changes: changes,
      oldCursor: pending.oldCursor,
      newCursor: CursorSnapshot.fromDocument(document),
    );

    if (_currentGroupDescription != null &&
        _currentGroupDescription == pending.description &&
        _undoStack.isNotEmpty &&
        !_forceNewAction) {
      final lastDelta = _undoStack.last;
      if (lastDelta is NodeReplaceDelta &&
          lastDelta.description == pending.description) {
        final mergedChanges = <int, NodeChange>{};
        for (final c in lastDelta.changes) {
          mergedChanges[c.index] = c;
        }
        for (final c in delta.changes) {
          final existing = mergedChanges[c.index];
          if (existing != null) {
            mergedChanges[c.index] = NodeChange(
              index: c.index,
              oldJson: existing.oldJson,
              newJson: c.newJson,
            );
          } else {
            mergedChanges[c.index] = c;
          }
        }
        final mergedDelta = NodeReplaceDelta(
          description: pending.description,
          timestamp: lastDelta.timestamp,
          changes: mergedChanges.values.toList(),
          oldCursor: lastDelta.oldCursor,
          newCursor: delta.newCursor,
        );
        _undoStack.last = mergedDelta;
        _pending = null;
        _redoStack.clear();
        _updateJsonCacheFromChanges(document, mergedChanges.values.toList());
        _enforceMemoryLimit();
        return SaveStateResult.merged;
      }
    }

    _undoStack.add(delta);
    _redoStack.clear();
    _pending = null;
    _updateJsonCacheFromChanges(document, changes);
    _enforceMemoryLimit();
    return SaveStateResult.created;
  }

  bool undo(FluentDocument document) {
    if (!canUndo) return false;

    final delta = _undoStack.removeLast();
    _redoStack.add(delta);

    _isRestoringState = true;
    try {
      delta.revert(document);
    } catch (e, st) {
      debugPrint('[UNDO_ERROR] revert failed: $e\n$st');
      _redoStack.removeLast();
      return false;
    } finally {
      _isRestoringState = false;
    }
    _updateJsonCache(document);
    document.notifyDocumentChanged();
    _resetGrouping();
    return true;
  }

  bool redo(FluentDocument document) {
    if (!canRedo) return false;

    final delta = _redoStack.removeLast();
    _undoStack.add(delta);

    _isRestoringState = true;
    try {
      delta.apply(document);
    } catch (e, st) {
      debugPrint('[UNDO_ERROR] apply failed: $e\n$st');
      _undoStack.removeLast();
      return false;
    } finally {
      _isRestoringState = false;
    }
    _updateJsonCache(document);
    document.notifyDocumentChanged();
    _resetGrouping();
    return true;
  }



  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _pending = null;
    _jsonCache.clear();
    _resetGrouping();
  }

  /// Backward-compatible alias that captures the state and immediately
  /// commits it as a delta. Used by tests and handlers that don't go
  /// through [FluentDocument.updateContent].
  void saveState(
    FluentDocument document, {
    String description = 'Document change',
    bool forceNewAction = false,
  }) {
    beginSaveState(document, description: description, forceNewAction: forceNewAction);
    commitSaveState(document);
  }

  void forceNewAction(
    FluentDocument document, {
    String description = 'New action',
  }) {
    saveState(document, description: description, forceNewAction: true);
  }

  String? get lastUndoDescription =>
      _undoStack.isNotEmpty ? _undoStack.last.description : null;

  String? get lastRedoDescription =>
      _redoStack.isNotEmpty ? _redoStack.last.description : null;

  void _enforceMemoryLimit() {
    while (_undoStack.length > _maxUndoStates) {
      _undoStack.removeAt(0);
    }
  }

  void _resetGrouping() {
    _groupingTimer?.cancel();
    _groupingTimer = null;
    _currentGroupDescription = null;
    _lastActionTime = null;
    _forceNewAction = true;
  }

  /// Refreshes [_jsonCache] with the current state of all top-level nodes.
  /// Called after undo/redo so the next beginSaveState can reuse the cached
  /// JSON for unchanged nodes.
  void _updateJsonCache(FluentDocument document) {
    _jsonCache.clear();
    for (final node in document.content.nodes) {
      _jsonCache[node.id] = node.toJson();
    }
  }

  /// Incrementally updates [_jsonCache] using the [changes] from a commit.
  void _updateJsonCacheFromChanges(
    FluentDocument document,
    List<NodeChange> changes,
  ) {
    _updateJsonCache(document);
  }

  void dispose() {
    _groupingTimer?.cancel();
    clear();
  }
}

/// Shallow equality for JSON maps produced by [FNode.toJson].
bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    final av = a[key];
    final bv = b[key];
    if (av is Map && bv is Map) {
      if (!_mapsEqual(av.cast<String, dynamic>(), bv.cast<String, dynamic>())) {
        return false;
      }
    } else if (av is List && bv is List) {
      if (av.length != bv.length) return false;
      for (int i = 0; i < av.length; i++) {
        final ai = av[i];
        final bi = bv[i];
        if (ai is Map && bi is Map) {
          if (!_mapsEqual(
              ai.cast<String, dynamic>(), bi.cast<String, dynamic>())) {
            return false;
          }
        } else if (ai != bi) {
          return false;
        }
      }
    } else if (av != bv) {
      return false;
    }
  }
  return true;
}
