import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/comments/comment_provider.dart';
import 'package:fluent_editor/spell_check/spell_check_provider.dart';
import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/selection_manager.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:fluent_editor/widgets/editor/fluent_toolbar_widget.dart';
import 'package:fluent_editor/widgets/nodes/virtualized_selectable_area.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/event_handler.dart';
import 'package:fluent_editor/core/paragraph_registry.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';
import 'package:fluent_editor/input/ime_handler.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';

class FluentDocument extends ChangeNotifier {
  /// Active font family for collapsed cursor (persistent like Word).
  /// When the user types, new text inherits this font.
  String pendingFontFamily = 'DejaVu Sans';

  /// True when an image resize handle is being dragged.
  /// Used to prevent text selection from interfering with image resize.
  bool isResizingImage = false;

  /// Active font size for collapsed cursor.
  double pendingFontSize = 14.0;

  /// Active line height for collapsed cursor.
  double pendingLineHeight = 1.15;

  /// Spacing before paragraph in points.
  double pendingSpacingBefore = 12.0;

  /// Spacing after paragraph in points.
  double pendingSpacingAfter = 12.0;

  /// Active text color for collapsed cursor. Null = auto.
  String? pendingColor;

  /// Active highlight color for collapsed cursor. Null = none.
  String? pendingHighlightColor;

  /// Active inline styles for collapsed cursor (bold, italic, underline).
  List<String> pendingStyles = [];

  /// Active text alignment for collapsed cursor (left, center, right).
  /// Used when creating a new paragraph.
  String pendingTextAlign = 'left';

  /// Active indentation for collapsed cursor.
  /// Used when creating a new paragraph.
  int pendingIndent = 0;

  /// Active style for collapsed cursor.
  /// Used when creating a new paragraph.
  ParagraphStyle pendingStyle = ParagraphStyle.normal;

  /// Document-level language (BCP-47 code). Defaults to the language
  /// selected in [DocumentLanguageController] or the system locale.
  String documentLanguage = DocumentLanguageController.instance.current.code;

  /// Optional spell-check plugin. When set, the editor will use it
  /// for underlining misspelled words and providing suggestions.
  SpellCheckProvider? spellCheckProvider;

  /// Optional comment plugin. When set, the editor will display
  /// comment highlights, a sidebar, and allow adding / managing comments.
  CommentProvider? commentProvider;

  /// Localization labels for the user interface.
  FluentEditorLabels? labels;

  /// Internal clipboard payload (JSON serialized) with preserved formatting.
  String? clipboardPayload;

  late Root _content;

  /// Monotonically incremented every time the document *content* (nodes/text)
  /// changes. Cursor movements alone do NOT bump it, allowing the widget to
  /// skip the expensive global setState when only the caret moved.
  int _contentVersion = 0;
  int get contentVersion => _contentVersion;

  /// O(1) lookup map from node id to node, rebuilt lazily when the
  /// document mutates. Replaces O(n) full-tree scans of [findById].
  final Map<String, FNode> _nodeById = {};
  bool _nodeIndexDirty = true;

  /// Returns the node with the given [id] in O(1) using a cached index.
  /// The index is rebuilt lazily (single tree walk) only when the document
  /// has changed since the last lookup.
  FNode? nodeById(String id) {
    if (_nodeIndexDirty) _rebuildNodeIndex();
    final cached = _nodeById[id];
    if (cached != null) return cached;
    // Fallback: the index may be stale if a mutation forgot to notify.
    // Rebuild once and retry before giving up.
    _rebuildNodeIndex();
    return _nodeById[id];
  }

  /// Rebuilds the id→node index with a single DFS walk over the whole tree.
  /// Also populates the node-position index so order comparisons are O(1),
  /// and the parent-cache so parent lookup is O(1).
  void _rebuildNodeIndex() {
    _nodeById.clear();
    _nodePositionIndex.clear();
    _parentCache.clear();
    int pos = 0;
    walkTree(_content, (node, parent) {
      _nodeById[node.id] = node;
      _nodePositionIndex[node.id] = pos++;
      _parentCache[node.id] = parent?.id;
      return true;
    });
    _nodeIndexDirty = false;
    _nodePositionIndexDirty = false;
    _parentCacheDirty = false;
    // Inject the freshly-built index into the selection manager so it can
    // compare node order correctly instead of relying on lexicographic UUIDs.
    _selectionManager.setPositionIndex(_nodePositionIndex);
  }

  /// O(1) lookup of the parent id of [childId].
  /// Returns null if [childId] is the root or not found.
  String? findParentCached(String childId) {
    if (_parentCacheDirty) _rebuildNodeIndex();
    return _parentCache[childId];
  }

  /// Marks the id→node index as stale so it gets rebuilt on next lookup.
  void invalidateNodeIndex() {
    _nodeIndexDirty = true;
    _nodePositionIndexDirty = true;
    _parentCacheDirty = true;
    _cachedStops = null;
    _cachedStopsByContainer = null;
    _cachedContainerOrder = null;
    _cachedLogicalLines = null;
    _flattenedCache = null;
    _logicalContainerCache.clear();
  }

  /// Linear position of each node in the document order (pre-order DFS).
  /// Used by selection to compare node order correctly instead of relying on
  /// lexicographic UUID comparison, which is pseudo-random and breaks selection
  /// logic for ~50% of node pairs.
  final Map<String, int> _nodePositionIndex = {};
  bool _nodePositionIndexDirty = true;

  /// Cached parent map: child id → parent id.
  /// Built during the same DFS walk as the node index, so there is zero
  /// extra cost. Invalidated together with the node index on any content
  /// change. Used by widgets that need O(1) parent lookup (e.g. context
  /// menu on right-click to detect if a fragment is inside a Link).
  final Map<String, String?> _parentCache = {};
  bool _parentCacheDirty = true;

  /// O(1) lookup of the document-order position of [nodeId].
  /// Returns null if the node is not found in the document.
  int? nodePosition(String nodeId) {
    if (_nodePositionIndexDirty) _rebuildNodeIndex();
    return _nodePositionIndex[nodeId];
  }

  /// Memoized fragmentId → logical-container-id lookups. Resolving a logical
  /// container walks the whole tree (O(n)); caching makes repeated lookups
  /// (e.g. shift+arrow selection, where the anchor is fixed and the focus
  /// often stays in the same fragment) O(1). Cleared on any content change.
  final Map<String, String?> _logicalContainerCache = {};

  /// Cached caret-stop rail used by arrow navigation. Building it walks the
  /// whole document (O(n)); caching avoids rebuilding it on every key press.
  /// Invalidated together with the node index on any content change.
  List<CaretStop>? _cachedStops;
  List<CaretStop> get caretStops {
    return _cachedStops ??= buildAllStops(_content);
  }

  /// Cached logical lines of the document. Used by Home/End/PageUp/PageDown
  /// to avoid rebuilding O(n) on every key press.
  List<LogicalLine>? _cachedLogicalLines;
  List<LogicalLine> get logicalLines {
    return _cachedLogicalLines ??= buildAllLogicalLines(_content);
  }

  /// Cached flattened fragment lists per container.
  /// Building it walks all fragments in a container (O(n_fragments));
  /// caching avoids rebuilding on repeated cursor / hit-test queries.
  Map<String, List<(Fragment, int, int)>>? _flattenedCache;

  /// Returns the flattened fragment list for [container] with global
  /// offsets, using the document cache when available.
  List<(Fragment, int, int)> flattenContainer(FNode container) {
    _flattenedCache ??= {};
    final cached = _flattenedCache![container.id];
    if (cached != null) return cached;
    final result = flattenFragmentsSimple(container);
    _flattenedCache![container.id] = result;
    return result;
  }

  /// Caret stops grouped by their logical container id.
  /// Lazily built from [caretStops] + [findLogicalContainerId]; invalidated
  /// on content change. Used by vertical navigation to scan only the stops
  /// of the relevant paragraph instead of the whole document.
  Map<String, List<CaretStop>>? _cachedStopsByContainer;
  Map<String, List<CaretStop>> get stopsByContainer {
    if (_cachedStopsByContainer != null) return _cachedStopsByContainer!;
    final map = <String, List<CaretStop>>{};
    for (final stop in caretStops) {
      final cid = findLogicalContainerId(stop.fragmentId);
      if (cid != null) {
        map.putIfAbsent(cid, () => []).add(stop);
      }
    }
    return _cachedStopsByContainer = map;
  }

  /// Ordered list of logical container ids matching the top-level node order.
  /// Used by vertical navigation to know the predecessor / successor container.
  List<String>? _cachedContainerOrder;
  List<String> get containerOrder {
    if (_cachedContainerOrder != null) return _cachedContainerOrder!;
    final ids = <String>[];
    for (final node in _content.nodes) {
      if (node is InlineContainerNode &&
          node is! FluentCell &&
          node is! ListItem &&
          node is! FluentTable &&
          node is! FluentList) {
        ids.add(node.id);
      } else if (node is FluentList) {
        for (final item in node.items) {
          _collectContainerOrderIds(item, ids);
        }
      } else if (node is FluentTable) {
        for (final row in node.rows) {
          for (final cell in row.cells) {
            _collectContainerOrderIds(cell, ids);
          }
        }
      }
    }
    return _cachedContainerOrder = ids;
  }

  /// Recursively collects ids of the actual logical containers inside
  /// [node] (Paragraphs, HRs, images) so that [containerOrder] aligns with
  /// what [findLogicalContainerId] returns.
  void _collectContainerOrderIds(FNode node, List<String> ids) {
    // FluentList and FluentTable MUST be checked before Paragraph because
    // FluentList extends Paragraph. If checked after, sublists are treated as
    // leaf nodes and their paragraph children are skipped.
    if (node is FluentList) {
      for (final item in node.items) {
        _collectContainerOrderIds(item, ids);
      }
      return;
    }
    if (node is FluentTable) {
      for (final row in node.rows) {
        for (final cell in row.cells) {
          _collectContainerOrderIds(cell, ids);
        }
      }
      return;
    }
    if (node is FluentCell || node is ListItem) {
      for (final child in childrenOf(node)) {
        _collectContainerOrderIds(child, ids);
      }
      return;
    }
    if (node is Paragraph || node is HorizontalRule) {
      ids.add(node.id);
      return;
    }
    if (node is FluentImage) {
      ids.add(node.id);
      return;
    }
    if (node is Link) {
      for (final child in childrenOf(node)) {
        _collectContainerOrderIds(child, ids);
      }
      return;
    }
    if (node is InlineContainerNode) {
      for (final child in childrenOf(node)) {
        _collectContainerOrderIds(child, ids);
      }
    }
  }

  FluentDocument({Root? content}) {
    _content = content ?? Root(nodes: [Paragraph(text: "")]);
    // Initialize cursor to point to first paragraph
    _cursor.document = this;
    if (_content.nodes.isNotEmpty) {
      final firstNode = _content.nodes.first;
      if (firstNode is Paragraph && firstNode.fragments.isNotEmpty) {
        final firstFrag = firstNode.fragments.first;
        if (firstFrag is Fragment) {
          _cursor.moveTo(firstFrag.id, 0);
        }
      }
    }
  }

  /// Creates a FluentDocument from a JSON map (result of jsonDecode).
  /// Supports both the new format (with "nodes" and "settings") and
  /// the legacy format (Root JSON directly).
  factory FluentDocument.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('nodes') && json.containsKey('settings')) {
      // New format: wrapped with settings
      final root = Root.fromJson(json['nodes'] as Map<String, dynamic>);
      final doc = FluentDocument(content: root);
      final settings = json['settings'] as Map<String, dynamic>;
      doc.pendingLineHeight = (settings['lineHeight'] as num?)?.toDouble() ?? doc.pendingLineHeight;
      doc.pendingSpacingBefore = (settings['spacingBefore'] as num?)?.toDouble() ?? doc.pendingSpacingBefore;
      doc.pendingSpacingAfter = (settings['spacingAfter'] as num?)?.toDouble() ?? doc.pendingSpacingAfter;
      doc.pendingFontFamily = settings['fontFamily'] as String? ?? doc.pendingFontFamily;
      doc.pendingFontSize = (settings['fontSize'] as num?)?.toDouble() ?? doc.pendingFontSize;
      doc.pendingTextAlign = settings['textAlign'] as String? ?? doc.pendingTextAlign;
      doc.pendingIndent = (settings['indent'] as num?)?.toInt() ?? doc.pendingIndent;
      doc.pendingColor = settings['color'] as String?;
      doc.pendingHighlightColor = settings['highlightColor'] as String?;
      if (settings['styles'] is List) {
        doc.pendingStyles = (settings['styles'] as List).map((e) => e as String).toList();
      }
      doc.documentLanguage = settings['documentLanguage'] as String? ?? doc.documentLanguage;
      // Restore comments if present
      final comments = json['comments'];
      if (comments is List && doc.commentProvider != null) {
        doc.commentProvider!.importComments(
          comments.map((e) => e as Map<String, dynamic>).toList(),
        );
      }
      return doc;
    }
    // Legacy format: Root JSON directly
    final root = Root.fromJson(json);
    return FluentDocument(content: root);
  }

  /// Loads new content into the document, resetting cursor and selection.
  void loadContent(Root newContent) {
    _content = newContent;
    invalidateNodeIndex();
    _cursor.moveTo(newContent.nodes.first.id, 0);
    _selectionManager.clear();
    updateContent();
  }

  Root get content => _content;

  final Cursor _cursor = Cursor();
  Cursor get cursor => _cursor;
  
  final SelectionManager _selectionManager = SelectionManager();
  SelectionManager get selectionManager => _selectionManager;

  final EventHandler _eventHandler = EventHandler();
  EventHandler get eventHandler => _eventHandler;

  final ParagraphRegistry _paragraphRegistry = ParagraphRegistry();
  ParagraphRegistry get paragraphRegistry => _paragraphRegistry;

  final UndoRedoManager _undoRedoManager = UndoRedoManager();
  UndoRedoManager get undoRedoManager => _undoRedoManager;

  final FluentTextInputHandler imeHandler = FluentTextInputHandler();

  /// Notifies the comment provider that text in [paragraphId] was mutated.
  void notifyTextMutation(String paragraphId, int fromOffset, int delta) {
    commentProvider?.onDocumentMutation(paragraphId, fromOffset, delta);
  }

  /// Calculates the global offset within [paragraphId] for a local
  /// (fragmentId, localOffset) pair. Returns null if the fragment is not found.
  int? getGlobalOffsetInParagraph(String paragraphId, String fragmentId, int localOffset) {
    final node = nodeById(paragraphId);
    if (node is! Paragraph) return null;
    int global = 0;
    bool found = false;
    void visit(FNode child) {
      if (found) return;
      if (child is Fragment) {
        if (child.id == fragmentId) {
          global += localOffset;
          found = true;
          return;
        }
        global += child.text.length;
      } else if (child is Link) {
        for (final linkChild in child.fragments) {
          if (found) return;
          if (linkChild is Fragment) {
            if (linkChild.id == fragmentId) {
              global += localOffset;
              found = true;
              return;
            }
            global += linkChild.text.length;
          }
        }
      }
    }
    for (final child in node.fragments) {
      visit(child);
    }
    return found ? global : null;
  }

  /// FocusNode for the editing area. The toolbar can request focus
  /// after an interaction (e.g., font selection) by calling [requestEditorFocus].
  final FocusNode editorFocusNode = FocusNode();
  void requestEditorFocus() => editorFocusNode.requestFocus();

  /// Opens the virtual keyboard via the IME handler.
  void requestMobileKeyboardFocus(BuildContext context) => imeHandler.showKeyboard(context);

  final Map<String, GlobalKey> _nodeKeys = {};
  GlobalKey getKeyForNode(String nodeId) {
    return _nodeKeys.putIfAbsent(nodeId, () => GlobalKey());
  }

  /// Executes undo of the last action
  bool undo() {
    return _undoRedoManager.undo(this);
  }

  /// Executes redo of the last undone action
  bool redo() {
    return _undoRedoManager.redo(this);
  }

  /// Checks if undo is possible
  bool get canUndo => _undoRedoManager.canUndo;

  /// Checks if redo is possible
  bool get canRedo => _undoRedoManager.canRedo;

  /// Begins capturing the old document state for a delta-based undo.
  /// The delta is committed automatically by [updateContent] after the
  /// mutation, producing a minimal undo record that stores only the
  /// changed top-level nodes (50-100x smaller than a full snapshot).
  void saveState({String description = 'Document change', bool forceNewAction = false}) {
    _undoRedoManager.beginSaveState(this, description: description, forceNewAction: forceNewAction);
  }

  /// Forces creation of a new action (not grouped)
  void forceNewAction({String description = 'New action'}) {
    _undoRedoManager.forceNewAction(this, description: description);
  }

  /// Clears undo/redo stacks
  void clearUndoRedo() {
    _undoRedoManager.clear();
  }

  /// Returns the id of the inline container that directly contains
  /// the fragment (Paragraph inside a ListItem/Cell, or standalone Paragraph).
  String? findLogicalContainerId(String fragmentId) {
    final cached = _logicalContainerCache[fragmentId];
    if (cached != null || _logicalContainerCache.containsKey(fragmentId)) {
      return cached;
    }
    final container = findLogicalContainer(_content, fragmentId);
    final id = container == null ? null : (container as FNode).id;
    _logicalContainerCache[fragmentId] = id;
    return id;
  }

  /// Caret coordinate resolver for vertical navigation.
  ///
  /// Optimized to O(1) by looking up the paragraph render directly via the
  /// fragment's logical container, instead of scanning every registered render.
  double resolveCaretX(CaretStop stop) {
    final containerId = findLogicalContainerId(stop.fragmentId);
    if (containerId != null) {
      final render = _paragraphRegistry.renderFor(containerId);
      final x = render?.getCaretX(stop.fragmentId, stop.offset);
      if (x != null) return x;
    }
    final box = _findBlockImageBox(stop.fragmentId);
    if (box == null) return 0.0;
    final origin = box.localToGlobal(Offset.zero);
    return origin.dx + (stop.offset == 0 ? 0 : box.size.width);
  }

  double resolveCaretY(CaretStop stop) {
    final containerId = findLogicalContainerId(stop.fragmentId);
    if (containerId != null) {
      final render = _paragraphRegistry.renderFor(containerId);
      final y = render?.getCaretY(stop.fragmentId, stop.offset);
      if (y != null) return y;
    }
    final box = _findBlockImageBox(stop.fragmentId);
    if (box == null) return 0.0;
    return box.localToGlobal(Offset.zero).dy;
  }

  RenderBox? _findBlockImageBox(String fragmentId) {
    final node = nodeById(fragmentId);
    if (node is! FluentImage) return null;
    final ctx = getKeyForNode(node.id).currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is RenderBox && ro.hasSize) return ro;
    return null;
  }

  void manageEvent(KeyEvent event) {
    if (cursor.anchorId == '') {
      cursor.anchorId = content.id;
      cursor.focusId = content.id;
    }
    _eventHandler.handle(event, this);
  }
  
  /// Helper to get the parent node ID of a fragment
  String? findParentNodeId(String fragmentId) {
    // Fast path: check if it's a top-level node
    for (var i = 0; i < _content.nodes.length; i++) {
      if (_content.nodes[i].id == fragmentId) {
        return _content.id; // Root document is the parent
      }
    }
    
    // Search in nested structures
    for (final node in _content.nodes) {
      final found = _findInNode(node, fragmentId, _content.id);
      if (found != null) return found;
    }
    return null;
  }
  
  String? _findInNode(FNode node, String fragmentId, String parentId) {
    if (node.id == fragmentId) return parentId;
    
    if (node is InlineContainerNode) {
      for (final child in (node as InlineContainerNode).getChildren()) {
        final found = _findInNode(child, fragmentId, node.id);
        if (found != null) return found;
      }
    }
    
    if (node is FluentList) {
      for (final item in node.items) {
        final found = _findInNode(item, fragmentId, node.id);
        if (found != null) return found;
      }
    }
    
    return null;
  }
  
  /// Gets the hierarchical path of a node in the document
  List<int>? getNodePath(String nodeId) {
    // Fast path: check if it's a top-level node
    for (var i = 0; i < _content.nodes.length; i++) {
      if (_content.nodes[i].id == nodeId) {
        return [i];
      }
    }
    
    // Search in nested structures
    for (var i = 0; i < _content.nodes.length; i++) {
      final found = _findNodePathRecursive(_content.nodes[i], nodeId, [i]);
      if (found != null) return found;
    }
    return null;
  }
  
  List<int>? _findNodePathRecursive(FNode node, String targetId, List<int> currentPath) {
    if (node.id == targetId) return currentPath;
    
    switch (node) {
      case FluentList list:
        for (var i = 0; i < list.items.length; i++) {
          final item = list.items[i];
          final newPath = [...currentPath, i];
          if (item.id == targetId) return newPath;
          final found = _findNodePathRecursive(item, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      case FluentTable table:
        for (var i = 0; i < table.rows.length; i++) {
          final row = table.rows[i];
          final newPath = [...currentPath, i];
          if (row.id == targetId) return newPath;
          final found = _findNodePathRecursive(row, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      case FluentRow row:
        for (var i = 0; i < row.cells.length; i++) {
          final cell = row.cells[i];
          final newPath = [...currentPath, i];
          if (cell.id == targetId) return newPath;
          final found = _findNodePathRecursive(cell, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      case FluentCell cell:
        for (var i = 0; i < cell.children.length; i++) {
          final child = cell.children[i];
          final newPath = [...currentPath, i];
          if (child.id == targetId) return newPath;
          final found = _findNodePathRecursive(child, targetId, newPath);
          if (found != null) return found;
        }
        break;

      case Paragraph paragraph when node is! ListItem && node is! Link:
        for (var i = 0; i < paragraph.fragments.length; i++) {
          final child = paragraph.fragments[i];
          final newPath = [...currentPath, i];
          if (child.id == targetId) return newPath;
          final found = _findNodePathRecursive(child, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      case ListItem item:
        for (var i = 0; i < item.children.length; i++) {
          final child = item.children[i];
          final newPath = [...currentPath, i];
          if (child.id == targetId) return newPath;
          final found = _findNodePathRecursive(child, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      case Link link:
        for (var i = 0; i < link.fragments.length; i++) {
          final child = link.fragments[i];
          final newPath = [...currentPath, i];
          if (child.id == targetId) return newPath;
          final found = _findNodePathRecursive(child, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      default:
        break;
    }
    
    return null;
  }
  
  bool isNodeSelected(String nodeId) {
    if (!_selectionManager.hasSelection) return false;

    final state = _selectionManager.state;
    final anchor = state.anchor;
    final focus = state.focus;

    if (anchor == null || focus == null) return false;

    // O(1) document-order lookup via the cached position index.
    // Replaces the O(n) getNodePath scan that was a major bottleneck
    // during drag selection on large documents.
    final nodePos = nodePosition(nodeId);
    final anchorPos = nodePosition(anchor.nodeId);
    final focusPos = nodePosition(focus.nodeId);

    if (nodePos == null || anchorPos == null || focusPos == null) return false;

    final basePos = anchorPos <= focusPos ? anchorPos : focusPos;
    final extentPos = anchorPos <= focusPos ? focusPos : anchorPos;

    return nodePos >= basePos && nodePos <= extentPos;
  }

  ({String startFrag, int startOff, String endFrag, int endOff})? getSelectionRangeForNode(String nodeId) {
    if (!_selectionManager.hasSelection) return null;
    if (!isNodeSelected(nodeId)) return null;

    final state = _selectionManager.state;
    final anchor = state.anchor!;
    final focus = state.focus!;

    // O(1) document-order position lookups instead of O(n) getNodePath.
    final nodePos = nodePosition(nodeId);
    final anchorPos = nodePosition(anchor.nodeId);
    final focusPos = nodePosition(focus.nodeId);

    if (nodePos == null || anchorPos == null || focusPos == null) return null;

    final base = anchorPos <= focusPos ? anchor : focus;
    final extent = anchorPos <= focusPos ? focus : anchor;
    final basePos = anchorPos <= focusPos ? anchorPos : focusPos;
    final extentPos = anchorPos <= focusPos ? focusPos : anchorPos;

    final isBaseNode = nodePos == basePos;
    final isExtentNode = nodePos == extentPos;

    if (isBaseNode && isExtentNode) {
      return (
        startFrag: base.fragmentId,
        startOff: base.offset,
        endFrag: extent.fragmentId,
        endOff: extent.offset,
      );
    } else if (isBaseNode) {
      return (
        startFrag: base.fragmentId,
        startOff: base.offset,
        endFrag: '',
        endOff: -1,
      );
    } else if (isExtentNode) {
      return (
        startFrag: '',
        startOff: 0,
        endFrag: extent.fragmentId,
        endOff: extent.offset,
      );
    } else {
      return (
        startFrag: '',
        startOff: 0,
        endFrag: '',
        endOff: -1,
      );
    }
  }

  void updateContent() {
    _contentVersion++;
    invalidateNodeIndex();
    // Commit any pending delta snapshot. This produces a minimal undo
    // record that stores only the changed top-level nodes, not the
    // entire document tree.
    _undoRedoManager.commitSaveState(this);
    notifyListeners();
  }

  /// Notifies document listeners that the content changed.
  /// Use this after undo/redo where [updateContent] must NOT be called
  /// (it would create a new undo record).
  ///
  /// If [affectedIds] is provided, only widgets for those node IDs will
  /// rebuild. If null, all widgets rebuild (backward-compatible).
  void notifyDocumentChanged({Set<String>? affectedIds}) {
    _dirtyNodeIds = affectedIds ?? {};
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dirtyNodeIds.clear();
    });
  }

  /// Returns true if [nodeId] was marked dirty by the last
  /// [notifyDocumentChanged] call. If no specific dirty nodes were set,
  /// returns true for all IDs (backward-compatible behaviour).
  bool isNodeDirty(String nodeId) =>
      _dirtyNodeIds.isEmpty || _dirtyNodeIds.contains(nodeId);

  /// True while listeners are being notified for a cursor-only change.
  /// Widgets that do expensive work on every document change can check this
  /// flag and skip irrelevant updates (e.g. toolbar style scan, full tree
  /// rebuild) when the document text / structure did not change.
  bool get cursorOnlyChange => _cursorOnlyChange;
  bool _cursorOnlyChange = false;

  /// IDs of nodes marked dirty by the last selective document change.
  /// Used by undo/redo to rebuild only the affected widgets.
  Set<String> _dirtyNodeIds = <String>{};

  // ─── Pre-computed cursor/selection cache ─────────────────────────
  // Populated once in cursorOnlyUpdate() before notifying listeners,
  // so every widget can read O(1) instead of re-running O(n) walks.
  String? _cachedCursorContainerId;
  final Set<String> _cachedSelectedNodeIds = <String>{};
  final Map<String, ({String startFrag, int startOff, String endFrag, int endOff})>
      _cachedSelectionRanges = {};

  /// O(1) when pre-computed, falls back to O(n) otherwise (e.g. drag selection).
  String? get cachedCursorContainerId {
    return _cachedCursorContainerId ??
        (cursor.focusId.isNotEmpty ? findLogicalContainerId(cursor.focusId) : null);
  }

  /// O(1) when pre-computed, falls back to O(n) otherwise (e.g. drag selection).
  bool isNodeSelectedCached(String nodeId) {
    if (_cachedSelectedNodeIds.isNotEmpty) {
      return _cachedSelectedNodeIds.contains(nodeId);
    }
    return selectionManager.isNodeSelected(nodeId);
  }

  /// O(1) when pre-computed, falls back to O(n) otherwise (e.g. drag selection).
  ({String startFrag, int startOff, String endFrag, int endOff})?
      getSelectionRangeCached(String nodeId) {
    if (_cachedSelectionRanges.containsKey(nodeId)) {
      return _cachedSelectionRanges[nodeId];
    }
    return getSelectionRangeForNode(nodeId);
  }

  /// Notifies listeners for a cursor/selection-only change that does NOT
  /// mutate the document structure or text. Crucially it does NOT invalidate
  /// the content-derived caches (node index, caret-stop rail), so repeated
  /// arrow navigation reuses them instead of rebuilding O(n) on every press.
  ///
  /// Listeners that are expensive on cursor-only changes can read
  /// [cursorOnlyChange] (true for the duration of this synchronous call) and
  /// skip unnecessary work.
  void cursorOnlyUpdate() {
    _cursorOnlyChange = true;

    // Pre-compute expensive lookups once before notifying 20+ widgets.
    // Each widget previously called findLogicalContainerId + isNodeSelected
    // + getSelectionRangeForNode independently — O(visible × n).
    // Now it's O(n) once, then O(1) per widget.
    _cachedCursorContainerId = cursor.focusId.isNotEmpty
        ? findLogicalContainerId(cursor.focusId)
        : null;

    _cachedSelectedNodeIds.clear();
    _cachedSelectionRanges.clear();
    if (selectionManager.hasSelection) {
      for (final node in _content.nodes) {
        final nodeId = node.id;
        if (selectionManager.isNodeSelected(nodeId)) {
          _cachedSelectedNodeIds.add(nodeId);
          final range = getSelectionRangeForNode(nodeId);
          if (range != null) {
            _cachedSelectionRanges[nodeId] = range;
          }
        }
      }
    }

    cursor.notifyListeners();
    notifyListeners();
    _cursorOnlyChange = false;
  }

  void syncPendingFontWithCursor() {
    if (cursor.isCollapsed) {
      final fragNode = nodeById(cursor.anchorId);
      final frag = fragNode is Fragment ? fragNode : null;
      pendingFontFamily = frag?.fontFamily ?? 'Arial';
      pendingFontSize = frag?.fontSize ?? 14.0;

      pendingColor = frag?.color;
      pendingHighlightColor = frag?.highlightColor;

      pendingStyles = List<String>.from(frag?.styles ?? []);

      final container = findLogicalContainer(_content, cursor.anchorId);
      if (container is Paragraph) {
        pendingTextAlign = container.textAlign;
        pendingIndent = container.indent;
        pendingStyle = container.getStyle();
      }
    }
  }

  void load(List<FNode> data) {
    _content.nodes = data;
    _contentVersion++;
    invalidateNodeIndex();
    notifyListeners();
  }

  String toJson() {
    final json = <String, dynamic>{
      'nodes': _content.toJson(),
      'settings': {
        'lineHeight': pendingLineHeight,
        'spacingBefore': pendingSpacingBefore,
        'spacingAfter': pendingSpacingAfter,
        'fontFamily': pendingFontFamily,
        'fontSize': pendingFontSize,
        'textAlign': pendingTextAlign,
        'indent': pendingIndent,
        'color': pendingColor,
        'highlightColor': pendingHighlightColor,
        'styles': pendingStyles,
        'documentLanguage': documentLanguage,
      },
    };
    if (commentProvider != null) {
      json['comments'] = commentProvider!.exportComments();
    }
    var encoder = const JsonEncoder.withIndent(' ');
    return encoder.convert(json);
  }
}

class FluentDocumentWidget extends StatefulWidget {
  const FluentDocumentWidget({
    super.key,
    required this.document,
    this.maxWidth = 800.0,
    this.labels,
    this.sidebar,
  });

  final FluentDocument document;
  final double maxWidth;
  final FluentEditorLabels? labels;
  final Widget? sidebar;

  @override
  State<FluentDocumentWidget> createState() => _FluentDocumentWidgetState();
}

/// Provides layout references (scroll controller + content stack key)
/// so that sidebars can compute positions relative to the shared Stack.
class DocumentLayout extends InheritedWidget {
  final ScrollController scrollController;
  final GlobalKey contentStackKey;

  const DocumentLayout({
    super.key,
    required this.scrollController,
    required this.contentStackKey,
    required super.child,
  });

  static DocumentLayout? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DocumentLayout>();
  }

  @override
  bool updateShouldNotify(DocumentLayout old) =>
      scrollController != old.scrollController ||
      contentStackKey != old.contentStackKey;
}

class _FluentDocumentWidgetState extends State<FluentDocumentWidget> {
  bool _showStatsPanel = false;
  bool _isSidebarCollapsed = false;
  bool _pendingScrollToCursor = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contentStackKey = GlobalKey();
  // REMOVED: _scrollViewKey - no longer needed with virtualization

  // REMOVED: _buildNodes - no longer used since virtualization is always enabled

  // Performance optimization: cache node index lookups
  final Map<String, int> _nodeIndexCache = {};
  bool _nodeIndexCacheDirty = true;

  // Measured item heights from the virtualized list for accurate scroll
  // positioning. Keys are node indices, values are actual rendered heights.
  final Map<int, double> _itemHeights = {};
  double _averageItemHeight = 40.0;

  // Cursor blink driver. A single periodic timer toggles the caret visibility
  // and repaints only the paragraph that owns the caret (O(1)).
  Timer? _blinkTimer;
  static const Duration _blinkInterval = Duration(milliseconds: 530);

  /// Repaints the paragraph that currently owns the caret, if rendered.
  void _repaintCaretParagraph() {
    final doc = widget.document;
    final cursor = doc.cursor;
    final fragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    if (fragId.isEmpty) return;
    final containerId = doc.findLogicalContainerId(fragId);
    if (containerId == null) return;
    doc.paragraphRegistry.renderFor(containerId)?.markNeedsPaint();
  }

  DateTime? _lastBlinkRestart;

  /// (Re)starts the blink cycle with the caret visible. Called on init and on
  /// every cursor/document change so the caret restarts solid after movement.
  /// Debounced: during key-hold events arrive at 30-60 Hz; restarting the
  /// timer that often is wasteful. We only restart if >200 ms elapsed.
  void _restartBlink() {
    final now = DateTime.now();
    if (_lastBlinkRestart != null &&
        now.difference(_lastBlinkRestart!).inMilliseconds < 200) {
      // Just force the caret visible without touching the timer.
      widget.document.paragraphRegistry.caretVisible = true;
      _repaintCaretParagraph();
      return;
    }
    _lastBlinkRestart = now;
    _blinkTimer?.cancel();
    widget.document.paragraphRegistry.caretVisible = true;
    _repaintCaretParagraph();
    _blinkTimer = Timer.periodic(_blinkInterval, (_) {
      final registry = widget.document.paragraphRegistry;
      registry.caretVisible = !registry.caretVisible;
      _repaintCaretParagraph();
    });
  }

  Widget _buildVirtualizedContent() {
    return Focus(
      focusNode: widget.document.editorFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        // TEMP DIAGNOSTIC — remove once the start-of-paragraph backspace bug
        // is confirmed fixed. Confirms whether onKeyEvent fires at all for
        // backspace from the iOS software keyboard.
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          debugPrint(
            'FluentDocument[DIAG]: onKeyEvent backspace, '
            'cursorIsAtFragmentStart=${widget.document.imeHandler.cursorIsAtFragmentStart}, '
            'isComposing=${widget.document.imeHandler.isComposing}, '
            'eventType=${event.runtimeType}',
          );
        }

        // During IME composition, let the IME handle navigation and character
        // keys. Arrow keys are routed to the IME (KeyEventResult.ignored) so
        // the user can navigate within the marked text to edit portions of the
        // composition (native macOS behavior). Only Ctrl/Meta shortcuts are
        // intercepted by the editor.
        if (widget.document.imeHandler.isComposing) {
          final isCtrl = HardwareKeyboard.instance.isControlPressed;
          final isMeta = HardwareKeyboard.instance.isMetaPressed;
          if (isCtrl || isMeta) {
            widget.document.manageEvent(event);
            return KeyEventResult.handled;
          }
          // Everything else (arrows, chars, backspace, enter) goes to the IME.
          return KeyEventResult.ignored;
        }

        // On desktop with an active TextInput connection, printable character
        // keys must propagate to FlutterTextInputPlugin (secondary responder)
        // so it calls interpretKeyEvents: on NSTextInputContext, activating the
        // CJK candidate window. Returning ignored here does NOT prevent the
        // character from being inserted — it arrives back via
        // updateEditingValueWithDeltas → _insertFinalizedText.
        // Backspace, Delete, Enter and all nav keys are handled directly here.
        final _isDesktop = !kIsWeb && (
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);
        if (_isDesktop && widget.document.imeHandler.isConnectionActive) {
          final _isCtrl = HardwareKeyboard.instance.isControlPressed;
          final _isMeta = HardwareKeyboard.instance.isMetaPressed;
          if (!_isCtrl && !_isMeta) {
            final _ch = event.character;
            final _isPrintable = _ch != null &&
                _ch.isNotEmpty &&
                _ch.runes.every((r) => r >= 32 && r != 127);
            if (_isPrintable) return KeyEventResult.ignored;
          }
        }

        // iOS virtual keyboard: backspace is handled via TextEditingDelta so the
        // IME buffer stays in sync with the document. macOS physical keyboard:
        // backspace is a hardware KeyEvent; the delta model is unreliable there,
        // so we let the KeyEvent path handle it and re-sync the buffer afterwards.
        final _isVirtualKeyboard = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
        if (_isVirtualKeyboard &&
            widget.document.imeHandler.shouldUseBufferSync &&
            widget.document.cursor.isCollapsed &&
            !widget.document.imeHandler.isComposing &&
            (event.logicalKey == LogicalKeyboardKey.backspace ||
             event.logicalKey == LogicalKeyboardKey.delete)) {
          // iOS virtual keyboard does not generate KeyUp/KeyRepeat events —
          // only physical keyboards do. Swallow KeyUp and KeyRepeat to
          // prevent the IME from generating a stale deletion delta echo
          // that would cascade into a backspace loop.
          if (event is! KeyDownEvent) {
            return KeyEventResult.handled;
          }
          // When the cursor is at the very start of the current fragment the
          // platform IME buffer has no text before the cursor, so iOS will
          // not emit a deletion delta. We must handle the structural backspace
          // (merge with previous node) ourselves.
          if (widget.document.imeHandler.cursorIsAtFragmentStart) {
            widget.document.manageEvent(event);
            widget.document.imeHandler.markBackspaceHandledViaKeyEvent();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        // All non-printable events (nav, backspace, enter, shortcuts).
        widget.document.manageEvent(event);
        return KeyEventResult.handled;
      },
      child: Padding(
        padding: const EdgeInsets.all(24.0).copyWith(
          right: 24.0 + (widget.sidebar == null || _isSidebarCollapsed ? 0 : 280),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: VirtualizedSelectableArea(
              document: widget.document,
              scrollController: _scrollController,
              itemCount: widget.document.content.nodes.length,
              onHeightsChanged: (heights) {
                _itemHeights.clear();
                _itemHeights.addAll(heights);
                if (heights.isNotEmpty) {
                  final sum = heights.values.reduce((a, b) => a + b);
                  _averageItemHeight = sum / heights.length;
                }
              },
              itemBuilder: (context, index) {
                final node = widget.document.content.nodes[index];
                return buildFNodeWidget(node, widget.document);
              },
            ),
          ),
        ),
      ),
    );
  }

  // REMOVED: _buildOriginalContent - no longer needed since virtualization is always used

  /// Resolves the current caret screen rect and forwards it to the IME so
  /// macOS can position the candidate window next to the cursor.
  /// Uses two nested postFrameCallbacks: the first waits for the current frame
  /// to complete (setState/layout), the second waits for the following paint so
  /// the render object coordinates are guaranteed to be up-to-date.
  void _updateImeCaretRect() {
    final cursor = widget.document.cursor;
    final fragId = cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    if (fragId.isEmpty) return;
    final offset = cursor.focusId.isNotEmpty ? cursor.focusOffset : cursor.anchorOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final rect = widget.document.paragraphRegistry.resolveCaretScreenRect(fragId, offset);
        if (rect != null && (rect.width > 0 || rect.height > 0)) {
          final view = View.of(context);
          final viewH = view.physicalSize.height / view.devicePixelRatio;
          widget.document.imeHandler.setViewHeight(viewH);
          widget.document.imeHandler.updateCaretRect(rect);
        }
      });
    });
  }

  void _onDocumentChanged() {
    _updateImeCaretRect();
    widget.document.imeHandler.syncImeBufferToFragment();

    if (widget.document.cursorOnlyChange) {
      // Cursor/selection-only change: the visible paragraphs already listen
      // to cursor/selectionManager and call their own setState. Avoid the
      // expensive global setState that rebuilds the whole editor shell.
      // Just ensure the cursor is visible.
      if (!_pendingScrollToCursor) {
        _pendingScrollToCursor = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _pendingScrollToCursor = false;
          _ensureCursorVisible();
        });
      }
      return;
    }

    // Content actually mutated: full rebuild (toolbar, sidebar, stats).
    setState(() {});

    // Any content change restarts the blink so the caret is solid
    // right after an edit, then resumes blinking.
    _restartBlink();
    // Invalidate node index cache when the content actually mutated.
    _nodeIndexCacheDirty = true;
    if (!_pendingScrollToCursor) {
      _pendingScrollToCursor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pendingScrollToCursor = false;
        _ensureCursorVisible();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
    // Attach the IME handler on all platforms so system IME (CJK, emoji,
    // voice dictation, etc.) works everywhere.
    widget.document.imeHandler.attachInput(widget.document);
    // Open/commit the IME connection with focus changes. On desktop
    // showKeyboard() must be called when focus is gained so the platform
    // activates the text input context (required for physical CJK keyboards).
    widget.document.editorFocusNode.addListener(_onEditorFocusChanged);
    // Register a global HardwareKeyboard handler so shortcuts and navigation
    // are intercepted even when the platform text input owns focus.
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
    if (widget.document.content.nodes.isNotEmpty) {
      widget.document.cursor.document = widget.document;
      widget.document.eventHandler.document = widget.document;
      final firstNode = widget.document.content.nodes[0];
      if (firstNode is Paragraph && firstNode.fragments.isNotEmpty) {
        final firstFrag = firstNode.fragments.first;
        if (firstFrag is Fragment) {
          widget.document.cursor.moveTo(firstFrag.id, 0);
        } else {
          widget.document.cursor.moveTo(firstNode.id, 0);
        }
      } else {
        widget.document.cursor.moveTo(firstNode.id, 0);
      }
    }
    widget.document.saveState(description: 'Initial state', forceNewAction: true);
    // Open the IME connection after the first frame so the OS registers
    // an active text-input context for physical CJK keyboards.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.document.imeHandler.showKeyboard(context);
    });
    _initSpellCheck();
    DocumentLanguageController.instance.currentLanguage
        .addListener(_onLanguageChanged);
    // Start the caret blink cycle (repaints only the caret paragraph).
    _restartBlink();
  }

  void _initSpellCheck() async {
    await DocumentLanguageController.instance.initialize();
    widget.document.documentLanguage =
        DocumentLanguageController.instance.current.code;
    final provider = widget.document.spellCheckProvider;
    if (provider != null) {
      await provider.initialize(widget.document.documentLanguage);
    }
  }

  void _onLanguageChanged() {
    final newLang = DocumentLanguageController.instance.current.code;
    if (widget.document.documentLanguage != newLang) {
      widget.document.documentLanguage = newLang;
      final provider = widget.document.spellCheckProvider;
      provider?.reloadLanguage(newLang);
    }
  }

  void _onEditorFocusChanged() {
    if (widget.document.editorFocusNode.hasFocus) {
      // Activates NSTextInputContext on macOS (and the equivalent on other
      // desktop platforms) so physical CJK keyboards show the IME panel.
      widget.document.imeHandler.showKeyboard(context);
    } else {
      widget.document.imeHandler.commitIfComposing();
    }
  }

  /// Global HardwareKeyboard handler active on all platforms.
  /// Intercepts shortcuts and navigation keys so they reach the EventHandler
  /// even when the platform text input owns focus.
  ///
  /// During an active IME composition all non-navigation keys are suppressed
  /// so the system IME receives them instead of the raw key pipeline.
  bool _onHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final doc = widget.document;
    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed;
    final isMeta = keyboard.isMetaPressed;
    final key = event.logicalKey;

    // Navigation keys are always routed through the editor.
    // Note: backspace and delete are excluded here to avoid double-handling
    // since they're also handled by the Focus widget's onKeyEvent.
    final navKeys = {
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
    };



    // When our editor FocusNode already has focus, the Focus widget's
    // onKeyEvent handles most keys. However, some OS-level shortcuts
    // (e.g. Cmd+Z on macOS) are consumed by the platform before they
    // reach our Focus widget, so we must intercept them at the global
    // handler level.
    final shortcutKeys = {
      LogicalKeyboardKey.keyZ,
    };
    if (doc.editorFocusNode.hasFocus && !shortcutKeys.contains(key)) {
      return false;
    }

    // During active IME composition, let the IME consume everything (including
    // arrow keys, so the user can navigate within the marked text to edit the
    // composition — native macOS behavior). Only Ctrl/Meta shortcuts are
    // intercepted by the editor.
    if (doc.imeHandler.isComposing) {
      if (isCtrl || isMeta) {
        doc.manageEvent(event);
        return true;
      }
      return false; // Let IME consume everything else (incl. arrows)
    }

    // iOS virtual keyboard: backspace is handled via TextEditingDelta.
    // macOS physical keyboard: backspace is a hardware KeyEvent; the delta
    // model is unreliable there, so we let the KeyEvent path handle it.
    final _isVirtualKeyboard = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
    if (_isVirtualKeyboard &&
        doc.imeHandler.shouldUseBufferSync &&
        doc.cursor.isCollapsed &&
        !doc.imeHandler.isComposing &&
        (key == LogicalKeyboardKey.backspace ||
         key == LogicalKeyboardKey.delete)) {
      return false;
    }

    // Shortcut combos (Ctrl/Meta + key)
    if (isCtrl || isMeta) {
      doc.manageEvent(event);
      return true;
    }

    if (navKeys.contains(key)) {
      doc.manageEvent(event);
      return true;
    }

    // Normal character input: prefer the IME channel (TextInput) so the platform
    // can run interpretKeyEvents: / NSTextInputContext for CJK keyboards.
    // Fall back to direct insertion only if the TextInput connection is not active.
    if (doc.imeHandler.isConnectionActive) return false;
    doc.manageEvent(event);
    return true;
  }

  void _ensureCursorVisible() {
    // ALWAYS USE VIRTUALIZED CURSOR VISIBILITY
    _ensureCursorVisibleVirtualized();
  }

  void _ensureCursorVisibleVirtualized() {
    // For virtualized content, we need to find which node contains the cursor
    // and scroll to that approximate position
    final cursor = widget.document.cursor;
    if (cursor.anchorId.isEmpty) return;

    // Use cached node index lookup for O(1) performance
    final cursorNodeIndex = _findNodeIndexCached(cursor.anchorId);
    if (cursorNodeIndex == -1) return;

    // Post-frame callback to ensure ListView is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      // Compute cumulative offset up to the cursor node using measured
      // heights when available, falling back to the average for unseen
      // nodes. This is critical for large paragraphs where 40px guesses
      // are wildly wrong.
      double nodeStart = 0.0;
      for (int i = 0; i < cursorNodeIndex; i++) {
        nodeStart += _itemHeights[i] ?? _averageItemHeight;
      }
      final nodeHeight = _itemHeights[cursorNodeIndex] ?? _averageItemHeight;
      final nodeEnd = nodeStart + nodeHeight;

      final position = _scrollController.position;
      const margin = 80.0;
      final viewportStart = position.pixels;
      final viewportEnd   = viewportStart + position.viewportDimension;

      if (nodeStart >= viewportStart + margin &&
          nodeEnd   <= viewportEnd   - margin) {
        return; // Already well inside viewport — nothing to do.
      }

      double scrollTarget;
      if (nodeEnd > viewportEnd - margin) {
        scrollTarget = nodeEnd + margin - position.viewportDimension;
      } else {
        scrollTarget = nodeStart - margin;
      }

      final clampedOffset = scrollTarget.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.jumpTo(clampedOffset.toDouble());
    });
  }

  /// Optimized node index lookup with caching
  int _findNodeIndexCached(String fragmentId) {
    _updateNodeIndexCacheIfNeeded();
    
    // First try direct node lookup
    final directIndex = _nodeIndexCache[fragmentId];
    if (directIndex != null) return directIndex;
    
    // If not found directly, search in fragments (this is more expensive)
    for (int i = 0; i < widget.document.content.nodes.length; i++) {
      final node = widget.document.content.nodes[i];
      if (_nodeContainsFragment(node, fragmentId)) {
        return i;
      }
    }
    
    return -1;
  }

  /// Updates node index cache when document changes
  void _updateNodeIndexCacheIfNeeded() {
    if (!_nodeIndexCacheDirty) return;
    
    _nodeIndexCache.clear();
    for (int i = 0; i < widget.document.content.nodes.length; i++) {
      final node = widget.document.content.nodes[i];
      _nodeIndexCache[node.id] = i;
      
      // Also cache fragment IDs for faster lookup
      if (node is Paragraph) {
        for (final fragment in node.fragments) {
          _nodeIndexCache[fragment.id] = i;
        }
      }
    }
    
    _nodeIndexCacheDirty = false;
  }

  BuildContext? _findVirtualizedAreaContext() {
    // Try to find the VirtualizedSelectableArea context
    // This is a simplified approach - return the current context for now
    // In a more robust implementation, you'd store a reference to the virtualized area
    return context;
  }

  bool _nodeContainsFragment(FNode node, String fragmentId) {
    if (node.id == fragmentId) return true;
    
    if (node is Paragraph) {
      return node.fragments.any((frag) => frag.id == fragmentId);
    }
    
    // For other container types, you might need to recurse
    return false;
  }

  @override
  void didUpdateWidget(FluentDocumentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    widget.document.removeListener(_onDocumentChanged);
    widget.document.editorFocusNode.removeListener(_onEditorFocusChanged);
    DocumentLanguageController.instance.currentLanguage
        .removeListener(_onLanguageChanged);
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          FluentToolbar(document: widget.document, labels: widget.labels),
          Expanded(
            child: Stack(
              children: [
                Stack(
                  children: [
                    // ALWAYS USE VIRTUALIZED CONTENT - INTEGRATE ALL FEATURES HERE
                    _buildVirtualizedContent(),
                    if (widget.sidebar != null && !_isSidebarCollapsed)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: 280,
                        child: DocumentLayout(
                          scrollController: _scrollController,
                          contentStackKey: _contentStackKey,
                          child: widget.sidebar!,
                        ),
                      ),
                  ],
                ),
                if (_showStatsPanel)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${widget.labels?.wordCount ?? "Words"}: ${_countWords()}'),
                          const SizedBox(width: 16),
                          Text('Chars: ${_countChars()}'),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: _showStatsPanel ? 80 : 16,
                  right: 16,
                  child: IconButton(
                    icon: Icon(_showStatsPanel ? Icons.close : Icons.info_outline),
                    onPressed: () {
                      setState(() {
                        _showStatsPanel = !_showStatsPanel;
                      });
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                if (widget.sidebar != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(20),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: IconButton(
                        icon: Icon(
                          _isSidebarCollapsed
                              ? Icons.chevron_left
                              : Icons.chevron_right,
                        ),
                        tooltip: _isSidebarCollapsed
                            ? (widget.labels?.showCommentsLabel ?? 'Show comments')
                            : (widget.labels?.hideCommentsLabel ?? 'Hide comments'),
                        onPressed: () {
                          setState(() {
                            _isSidebarCollapsed = !_isSidebarCollapsed;
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _countWords() {
    int count = 0;
    final root = widget.document.content;
    
    void visit(FNode node) {
      if (node is Fragment) {
        final text = node.text;
        if (text.isNotEmpty) {
          final words = text.split(RegExp(r'\s+'));
          count += words.where((w) => w.isNotEmpty).length;
        }
      } else if (node is InlineContainerNode) {
        for (final child in childrenOf(node)) {
          visit(child);
        }
      } else if (node is FluentList) {
        for (final item in node.items) {
          visit(item);
        }
      }
    }
    
    visit(root);
    return count;
  }

  int _countChars() {
    int count = 0;
    final root = widget.document.content;

    void visit(FNode node) {
      if (node is Fragment) {
        count += node.text.length;
      } else if (node is InlineContainerNode) {
        for (final child in childrenOf(node)) {
          visit(child);
        }
      } else if (node is FluentList) {
        for (final item in node.items) {
          visit(item);
        }
      }
    }

    visit(root);
    return count;
  }
}