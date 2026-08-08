import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/comments/comment_provider.dart';
import 'package:fluent_editor/suggestions/suggestion_provider.dart';
import 'package:fluent_editor/suggestions/suggestion_style_hook.dart';
export 'package:fluent_editor/suggestions/suggestion_style_hook.dart';
import 'package:fluent_editor/renderers/style_hook.dart';
export 'package:fluent_editor/renderers/style_hook.dart';
import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/selection_manager.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/event_handler.dart';
import 'package:fluent_editor/handlers/dialog_presenter.dart';
import 'package:fluent_editor/core/paragraph_registry.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';
export 'package:fluent_editor/undo_redo/undo_redo_manager.dart';
import 'package:fluent_editor/input/ime_handler.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/plugins/builtin_plugin.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';

class FluentDocument extends ChangeNotifier {
  /// Active font family for collapsed cursor (persistent like Word).
  /// When the user types, new text inherits this font.
  String pendingFontFamily = 'DejaVu Sans';

  /// True when an image resize handle is being dragged.
  /// Used to prevent text selection from interfering with image resize.
  bool isResizingImage = false;

  /// True when a table column/row/table resize handle is being dragged.
  /// Used to prevent text selection from interfering with table resize.
  bool isResizingTable = false;

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

  /// Optional comment plugin. When set, the editor will display
  /// comment highlights, a sidebar, and allow adding / managing comments.
  CommentProvider? commentProvider;

  /// Optional suggestion plugin / tracked changes provider.
  SuggestionProvider? suggestionProvider;

  /// Author name for comments, suggestions, and tracked changes export.
  String _authorName = '';

  String get authorName {
    if (commentProvider != null && commentProvider!.currentAuthor.isNotEmpty) {
      return commentProvider!.currentAuthor;
    }
    if (_authorName.isNotEmpty) {
      return _authorName;
    }
    if (labels?.defaultAuthorName != null && labels!.defaultAuthorName.isNotEmpty) {
      return labels!.defaultAuthorName;
    }
    return 'Author';
  }

  set authorName(String value) {
    _authorName = value;
    if (commentProvider != null) {
      commentProvider!.currentAuthor = value;
    }
    notifyListeners();
  }

  final List<RenderStyleHook> _styleHooks = [];

  /// Cached merged list of all active style hooks. Invalidated on mutation.
  List<RenderStyleHook>? _cachedAllStyleHooks;

  void _invalidateStyleHooksCache() {
    _cachedAllStyleHooks = null;
  }

  /// Active document-level rendering style hooks.
  List<RenderStyleHook> get styleHooks => List.unmodifiable(_styleHooks);

  /// Registers a rendering [styleHook] on this document.
  void addStyleHook(RenderStyleHook hook) {
    if (!_styleHooks.contains(hook)) {
      _styleHooks.add(hook);
      _invalidateStyleHooksCache();
      notifyListeners();
    }
  }

  /// Unregisters a rendering [styleHook] from this document.
  void removeStyleHook(RenderStyleHook hook) {
    if (_styleHooks.remove(hook)) {
      _invalidateStyleHooksCache();
      notifyListeners();
    }
  }

  /// All rendering style hooks active on this document, combining document-level
  /// [styleHooks] and registered plugin hooks (including suggestion rendering
  /// provided by [FluentSuggestionPlugin] via its [styleHook] override).
  ///
  /// The result is cached and reused across frames; invalidated automatically
  /// when hooks are added or removed.
  List<RenderStyleHook> get allStyleHooks {
    return _cachedAllStyleHooks ??= [
      ..._styleHooks,
      ...registry.styleHooks,
    ];
  }

  /// Hook configuration for suggestion addition and deletion styles.
  SuggestionStyleHook suggestionStyleHook = const SuggestionStyleHook();

  /// Localization labels for the user interface.
  FluentEditorLabels? labels;

  /// Internal clipboard payload (JSON serialized) with preserved formatting.
  String? clipboardPayload;

  late Root _content;

  /// Cached resolved selection keyed by cursor state. Populated by
  /// resolveSelectionFromCursor in handler_helpers.dart so multiple
  /// widgets (toolbar, font selector, font size selector) reuse the
  /// same ResolvedSelection instead of re-resolving O(n) each time.
  String? cachedSelectionKey;
  dynamic cachedSelection;

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
    return _nodeById[id];
  }

  /// Rebuilds the id→node index with a single DFS walk over the whole tree.
  /// Also populates the node-position index so order comparisons are O(1),
  /// and the parent-cache so parent lookup is O(1).
  void _rebuildNodeIndex() {
    _nodeById.clear();
    _nodePositionIndex.clear();
    _parentCache.clear();
    _topLevelIndex.clear();
    int pos = 0;
    for (int i = 0; i < _content.nodes.length; i++) {
      _topLevelIndex[_content.nodes[i].id] = i;
    }
    walkTree(_content, (node, parent) {
      _nodeById[node.id] = node;
      _nodePositionIndex[node.id] = pos++;
      _parentCache[node.id] = parent?.id;
      return true;
    });
    _nodeIndexDirty = false;
    _parentCacheDirty = false;
    _selectionManager.setPositionIndex(_nodePositionIndex);
  }

  /// O(1) lookup of the parent id of [childId].
  /// Returns null if [childId] is the root or not found.
  String? findParentCached(String childId) {
    if (_parentCacheDirty) _rebuildNodeIndex();
    return _parentCache[childId];
  }

  /// O(1) lookup of the top-level index for a node id, or -1 if not found.
  /// Uses [findLogicalContainerId] to resolve fragments to their container.
  int topLevelIndexOf(String fragmentOrNodeId) {
    if (_nodeIndexDirty) _rebuildNodeIndex();
    final idx = _topLevelIndex[fragmentOrNodeId];
    if (idx != null) return idx;
    final containerId = findLogicalContainerId(fragmentOrNodeId);
    if (containerId != null) return _topLevelIndex[containerId] ?? -1;
    return -1;
  }

  /// Marks the id→node index as stale so it gets rebuilt on next lookup.
  void invalidateNodeIndex() {
    _nodeIndexDirty = true;
    _parentCacheDirty = true;
    _cachedStops = null;
    _cachedStopsByContainer = null;
    _cachedContainerOrder = null;
    _cachedLogicalLines = null;
    _flattenedCache = null;
    _flattenedByFragIdCache = null;
    _logicalContainerCache.clear();
    cachedSelectionKey = null;
    cachedSelection = null;
  }

  /// Linear position of each node in the document order (pre-order DFS).
  /// Used by selection to compare node order correctly instead of relying on
  /// lexicographic UUID comparison, which is pseudo-random and breaks selection
  /// logic for ~50% of node pairs.
  final Map<String, int> _nodePositionIndex = {};

  /// Cached parent map: child id → parent id.
  /// Built during the same DFS walk as the node index, so there is zero
  /// extra cost. Invalidated together with the node index on any content
  /// change. Used by widgets that need O(1) parent lookup (e.g. context
  /// menu on right-click to detect if a fragment is inside a Link).
  final Map<String, String?> _parentCache = {};
  bool _parentCacheDirty = true;

  /// Top-level node id → index in root.nodes. Built during _rebuildNodeIndex
  /// so widget scroll-to-cursor can skip its own separate cache.
  final Map<String, int> _topLevelIndex = {};

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

  /// Cached fragment-id → (fragment, startOffset, endOffset) map per container.
  /// Built alongside [_flattenedCache] for O(1) lookup by fragment id.
  Map<String, Map<String, (Fragment, int, int)>>? _flattenedByFragIdCache;

  /// Returns the flattened fragment list for [container] with global
  /// offsets, using the document cache when available.
  List<(Fragment, int, int)> flattenContainer(FNode container) {
    _flattenedCache ??= {};
    _flattenedByFragIdCache ??= {};
    final cid = container.id;
    final cached = _flattenedCache![cid];
    if (cached != null) return cached;
    final result = flattenFragmentsSimple(container);
    _flattenedCache![cid] = result;
    final byId = <String, (Fragment, int, int)>{};
    for (final (frag, start, end) in result) {
      byId[frag.id] = (frag, start, end);
    }
    _flattenedByFragIdCache![cid] = byId;
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
    if (node is Link) {
      for (final child in childrenOf(node)) {
        _collectContainerOrderIds(child, ids);
      }
      return;
    }
    if (node is Paragraph || node is HorizontalRule || node is FluentImage) {
      ids.add(node.id);
      return;
    }
    if (node is FluentCell || node is ListItem || node is InlineContainerNode) {
      for (final child in childrenOf(node)) {
        _collectContainerOrderIds(child, ids);
      }
    }
  }

  FluentPluginRegistry? _registry;
  FluentPluginRegistry get registry =>
      _registry ??= createDefaultFluentPluginRegistry();

  /// Replaces the plugin registry with [registry].
  void replaceRegistry(FluentPluginRegistry registry) {
    _registry = registry;
  }

  FluentDocument({Root? content, FluentPluginRegistry? registry}) {
    _registry = registry;
    _content = content ?? Root(nodes: [Paragraph(text: "")]);
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
  factory FluentDocument.fromJson(
    Map<String, dynamic> json, {
    FluentPluginRegistry? registry,
  }) {
    FNodeJsonConverter.activeRegistry = registry;
    try {
      if (json.containsKey('nodes') && json.containsKey('settings')) {
        final root = Root.fromJson(json['nodes'] as Map<String, dynamic>);
        final doc = FluentDocument(content: root, registry: registry);
        final settings = json['settings'] as Map<String, dynamic>;
        doc.pendingLineHeight =
            (settings['lineHeight'] as num?)?.toDouble() ??
            doc.pendingLineHeight;
        doc.pendingSpacingBefore =
            (settings['spacingBefore'] as num?)?.toDouble() ??
            doc.pendingSpacingBefore;
        doc.pendingSpacingAfter =
            (settings['spacingAfter'] as num?)?.toDouble() ??
            doc.pendingSpacingAfter;
        doc.pendingFontFamily =
            settings['fontFamily'] as String? ?? doc.pendingFontFamily;
        doc.pendingFontSize =
            (settings['fontSize'] as num?)?.toDouble() ?? doc.pendingFontSize;
        doc.pendingTextAlign =
            settings['textAlign'] as String? ?? doc.pendingTextAlign;
        doc.pendingIndent =
            (settings['indent'] as num?)?.toInt() ?? doc.pendingIndent;
        doc.pendingColor = settings['color'] as String?;
        doc.pendingHighlightColor = settings['highlightColor'] as String?;
        if (settings['styles'] is List) {
          doc.pendingStyles = (settings['styles'] as List)
              .map((e) => e as String)
              .toList();
        }
        doc.documentLanguage =
            settings['documentLanguage'] as String? ?? doc.documentLanguage;
        final comments = json['comments'];
        if (comments is List && doc.commentProvider != null) {
          doc.commentProvider!.importComments(
            comments.map((e) => e as Map<String, dynamic>).toList(),
          );
        }
        return doc;
      }
      final root = Root.fromJson(json);
      return FluentDocument(content: root, registry: registry);
    } finally {
      FNodeJsonConverter.activeRegistry = null;
    }
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

  DialogPresenter? _dialogPresenter;
  DialogPresenter get dialogPresenter {
    _dialogPresenter ??= DialogPresenter(this);
    return _dialogPresenter!;
  }

  final ParagraphRegistry _paragraphRegistry = ParagraphRegistry();
  ParagraphRegistry get paragraphRegistry => _paragraphRegistry;

  final UndoRedoManager _undoRedoManager = UndoRedoManager();
  UndoRedoManager get undoRedoManager => _undoRedoManager;

  final FluentTextInputHandler imeHandler = FluentTextInputHandler();

  /// Notifies the comment provider and registered plugins that text in [paragraphId] was mutated.
  void notifyTextMutation(String paragraphId, int fromOffset, int delta) {
    commentProvider?.onDocumentMutation(paragraphId, fromOffset, delta);
    registry.dispatchTextMutation(paragraphId, fromOffset, delta);
  }

  /// Calculates the global offset within [paragraphId] for a local
  /// (fragmentId, localOffset) pair. Returns null if the fragment is not found.
  int? getGlobalOffsetInParagraph(
    String paragraphId,
    String fragmentId,
    int localOffset,
  ) {
    final node = nodeById(paragraphId);
    if (node is! Paragraph) return null;
    flattenContainer(node);
    final entry = _flattenedByFragIdCache?[paragraphId]?[fragmentId];
    if (entry != null) return entry.$2 + localOffset;
    return null;
  }

  /// FocusNode for the editing area. The toolbar can request focus
  /// after an interaction (e.g., font selection) by calling [requestEditorFocus].
  final FocusNode editorFocusNode = FocusNode();
  void requestEditorFocus() => editorFocusNode.requestFocus();

  /// Opens the virtual keyboard via the IME handler.
  void requestMobileKeyboardFocus(BuildContext context) =>
      imeHandler.showKeyboard(context);

  final Map<String, GlobalKey> _nodeKeys = {};
  GlobalKey getKeyForNode(String nodeId) {
    return _nodeKeys.putIfAbsent(nodeId, () => GlobalKey());
  }

  /// Executes undo of the last action
  bool undo() {
    final result = _undoRedoManager.undo(this);
    if (result) {
      syncPendingFontWithCursor();
      registry.dispatchUndo(this);
    }
    return result;
  }

  /// Executes redo of the last undone action
  bool redo() {
    final result = _undoRedoManager.redo(this);
    if (result) {
      syncPendingFontWithCursor();
      registry.dispatchRedo(this);
    }
    return result;
  }

  /// Checks if undo is possible
  bool get canUndo => _undoRedoManager.canUndo;

  /// Checks if redo is possible
  bool get canRedo => _undoRedoManager.canRedo;

  /// Begins capturing the old document state for a delta-based undo.
  /// The delta is committed automatically by [updateContent] after the
  /// mutation, producing a minimal undo record that stores only the
  /// changed top-level nodes (50-100x smaller than a full snapshot).
  void saveState({
    String description = 'Document change',
    bool forceNewAction = false,
  }) {
    registry.dispatchSaveState(this, description);
    _undoRedoManager.beginSaveState(
      this,
      description: description,
      forceNewAction: forceNewAction,
    );
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

  /// Returns the inline container node for [fragmentId] using the cached
  /// container-id + node index. O(1) on cache hit, O(n) on first lookup.
  /// Handlers should prefer this over findLogicalContainer(root, fragmentId).
  InlineContainerNode? findLogicalContainerCached(String fragmentId) {
    final containerId = findLogicalContainerId(fragmentId);
    if (containerId == null) return null;
    return nodeById(containerId) as InlineContainerNode?;
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

  bool manageEvent(KeyEvent event) {
    if (cursor.anchorId == '') {
      cursor.anchorId = content.id;
      cursor.focusId = content.id;
    }
    return _eventHandler.handle(event, this);
  }

  bool isNodeSelected(String nodeId) {
    return _selectionManager.isNodeSelected(nodeId);
  }

  ({String startFrag, int startOff, String endFrag, int endOff})?
  getSelectionRangeForNode(String nodeId) {
    return _selectionManager.getRangeForNode(nodeId);
  }

  void updateContent({Set<String>? affectedIds, String? targetNodeId}) {
    _contentVersion++;
    invalidateNodeIndex();
    final saveResult = _undoRedoManager.commitSaveState(this);
    registry.dispatchCommitSaveState(this, result: saveResult);

    if (affectedIds != null) {
      _dirtyNodeIds = affectedIds;
    } else if (targetNodeId != null) {
      _dirtyNodeIds = {targetNodeId};
    } else {
      final focusId = cursor.focusId;
      if (focusId.isNotEmpty) {
        final cid = cachedCursorContainerId;
        if (cid != null) {
          _dirtyNodeIds = {cid};
        }
      }
    }
    notifyListeners();
    if (_dirtyNodeIds.isNotEmpty) {
      try {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _dirtyNodeIds.clear();
        });
      } catch (_) {
        _dirtyNodeIds.clear();
      }
    }
  }

  /// Notifies document listeners that the content changed.
  /// Use this after undo/redo where [updateContent] must NOT be called
  /// (it would create a new undo record).
  ///
  /// If [affectedIds] is provided, only widgets for those node IDs will
  /// rebuild. If null, all widgets rebuild (backward-compatible).
  void notifyDocumentChanged({Set<String>? affectedIds}) {
    _contentVersion++;
    _dirtyNodeIds = affectedIds ?? {};
    _cachedCursorContainerId = cursor.focusId.isNotEmpty
        ? findLogicalContainerId(cursor.focusId)
        : null;
    cachedSelectionKey = null;
    cachedSelection = null;
    cursor.notifyListeners();
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dirtyNodeIds.clear();
    });
  }

  /// Returns true if [nodeId] was marked dirty by the last
  /// [notifyDocumentChanged] or [updateContent] call. If no specific dirty nodes were set,
  /// returns true for all IDs (backward-compatible behaviour).
  bool isNodeDirty(String nodeId) =>
      _dirtyNodeIds.isEmpty || _dirtyNodeIds.contains(nodeId);

  /// Returns true if all nodes are considered dirty (e.g. full document refresh).
  bool get isFullDocumentDirty => _dirtyNodeIds.isEmpty;

  /// True while listeners are being notified for a cursor-only change.
  /// Widgets that do expensive work on every document change can check this
  /// flag and skip irrelevant updates (e.g. toolbar style scan, full tree
  /// rebuild) when the document text / structure did not change.
  bool get cursorOnlyChange => _cursorOnlyChange;
  bool _cursorOnlyChange = false;

  /// IDs of nodes marked dirty by the last selective document change.
  /// Used by undo/redo to rebuild only the affected widgets.
  Set<String> _dirtyNodeIds = <String>{};

  String? _cachedCursorContainerId;

  /// O(1) when pre-computed, falls back to O(1) cache-miss otherwise.
  String? get cachedCursorContainerId {
    return _cachedCursorContainerId ??
        (cursor.focusId.isNotEmpty
            ? findLogicalContainerId(cursor.focusId)
            : null);
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

    _cachedCursorContainerId = cursor.focusId.isNotEmpty
        ? findLogicalContainerId(cursor.focusId)
        : null;
    cachedSelectionKey = null;
    cachedSelection = null;

    cursor.notifyListeners();
    notifyListeners();
    _cursorOnlyChange = false;
  }

  void syncPendingFontWithCursor() {
    if (cursor.isCollapsed) {
      final fragNode = nodeById(cursor.anchorId);
      final frag = fragNode is Fragment ? fragNode : null;
      pendingFontFamily = frag?.fontFamily ?? 'DejaVu Sans';
      pendingFontSize = frag?.fontSize ?? 14.0;

      pendingColor = frag?.color;
      pendingHighlightColor = frag?.highlightColor;

      pendingStyles = List<String>.from(frag?.styles ?? []);

      final container = findLogicalContainerCached(cursor.anchorId);
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
