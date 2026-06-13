import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluent_editor/controllers/document_language_controller.dart';
import 'package:fluent_editor/comments/comment_provider.dart';
import 'package:fluent_editor/spell_check/spell_check_provider.dart';
import 'package:fluent_editor/cursor.dart';
import 'package:fluent_editor/selection_manager.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:fluent_editor/widgets/editor/fluent_toolbar_widget.dart';
import 'package:fluent_editor/widgets/nodes/fluent_selection.dart';
import 'package:flutter/material.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/event_handler.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/handlers/handle_insert_character.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';
import 'package:fluent_editor/core/paragraph_registry.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';

class FluentDocument extends ChangeNotifier {
  /// Active font family for collapsed cursor (persistent like Word).
  /// When the user types, new text inherits this font.
  String pendingFontFamily = 'DejaVu Sans';

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

  /// Notifies the comment provider that text in [paragraphId] was mutated.
  void notifyTextMutation(String paragraphId, int fromOffset, int delta) {
    commentProvider?.onDocumentMutation(paragraphId, fromOffset, delta);
  }

  /// Calculates the global offset within [paragraphId] for a local
  /// (fragmentId, localOffset) pair. Returns null if the fragment is not found.
  int? getGlobalOffsetInParagraph(String paragraphId, String fragmentId, int localOffset) {
    final node = findById(content, paragraphId);
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

  /// FocusNode for the hidden TextField used for mobile keyboard support.
  /// This is exposed to allow requesting focus specifically for mobile virtual keyboard.
  FocusNode? mobileTextFieldFocusNode;
  void requestMobileKeyboardFocus() => mobileTextFieldFocusNode?.requestFocus();

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

  /// Saves current state for undo/redo
  void saveState({String description = 'Document change', bool forceNewAction = false}) {
    _undoRedoManager.saveState(this, description: description, forceNewAction: forceNewAction);
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
  /// This ID is used by SelectionManager: it must match the id
  /// of the widget that renders the text (Paragraph), so the comparison with
  /// `getNodePath` in the widget aligns the paths correctly.
  String? findLogicalContainerId(String fragmentId) {
    final container = findLogicalContainer(_content, fragmentId);
    if (container == null) return null;
    return (container as FNode).id;
  }

  /// Caret coordinate resolver for vertical navigation.
  /// Tries `paragraphRegistry` first; if the stop belongs to a block-level
  /// FluentImage (not registered as paragraph), derives coordinates from
  /// the widget's `RenderBox` via the node's `GlobalKey`.
  double resolveCaretX(CaretStop stop) {
    final fromParagraph = _paragraphRegistry.resolveCaretX(stop);
    if (fromParagraph != 0.0) return fromParagraph;
    final box = _findBlockImageBox(stop.fragmentId);
    if (box == null) return fromParagraph;
    final origin = box.localToGlobal(Offset.zero);
    // offset 0 = left edge, offset 1 = right edge
    return origin.dx + (stop.offset == 0 ? 0 : box.size.width);
  }

  double resolveCaretY(CaretStop stop) {
    final fromParagraph = _paragraphRegistry.resolveCaretY(stop);
    if (fromParagraph != 0.0) return fromParagraph;
    final box = _findBlockImageBox(stop.fragmentId);
    if (box == null) return fromParagraph;
    return box.localToGlobal(Offset.zero).dy;
  }

  RenderBox? _findBlockImageBox(String fragmentId) {
    final node = findById(_content, fragmentId);
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
    updateContent();
  }
  
  /// Helper to get the parent node ID of a fragment
  String? findParentNodeId(String fragmentId) {
    // Search recursively in document nodes
    for (final node in _content.nodes) {
      final found = _findInNode(node, fragmentId, _content.id);
      if (found != null) return found;
    }
    return null;
  }
  
  String? _findInNode(FNode node, String fragmentId, String parentId) {
    if (node.id == fragmentId) return parentId;
    
    // For InlineContainerNode (Paragraph, ListItem, Link, etc.), search in children
    if (node is InlineContainerNode) {
      for (final child in (node as InlineContainerNode).getChildren()) {
        final found = _findInNode(child, fragmentId, node.id);
        if (found != null) return found;
      }
    }
    
    // For FluentList, also search in ListItem (which are direct children)
    if (node is FluentList) {
      for (final item in node.items) {
        final found = _findInNode(item, fragmentId, node.id);
        if (found != null) return found;
      }
    }
    
    return null;
  }
  
  /// Gets the hierarchical path of a node in the document
  /// Ex: [2] for a root node at index 2
  /// Ex: [2, 0] for the first ListItem of the FluentList at index 2
  List<int>? getNodePath(String nodeId) {
    for (var i = 0; i < _content.nodes.length; i++) {
      if (_content.nodes[i].id == nodeId) return [i];
      // Search recursively in children
      final found = _findNodePathRecursive(_content.nodes[i], nodeId, [i]);
      if (found != null) return found;
    }
    return null;
  }
  
  List<int>? _findNodePathRecursive(FNode node, String targetId, List<int> currentPath) {
    if (node.id == targetId) return currentPath;
    
    // Complete switch to handle all container node types
    switch (node) {
      // === FLUENT LIST ===
      // Has items (ListItem) as direct children
      case FluentList list:
        for (var i = 0; i < list.items.length; i++) {
          final item = list.items[i];
          final newPath = [...currentPath, i];
          if (item.id == targetId) return newPath;
          final found = _findNodePathRecursive(item, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      // === FLUENT TABLE ===
      // Has rows (FluentRow) as direct children
      case FluentTable table:
        for (var i = 0; i < table.rows.length; i++) {
          final row = table.rows[i];
          final newPath = [...currentPath, i];
          if (row.id == targetId) return newPath;
          final found = _findNodePathRecursive(row, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      // === FLUENT ROW ===
      // Has cells (FluentCell) as direct children
      case FluentRow row:
        for (var i = 0; i < row.cells.length; i++) {
          final cell = row.cells[i];
          final newPath = [...currentPath, i];
          if (cell.id == targetId) return newPath;
          final found = _findNodePathRecursive(cell, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      // === FLUENT CELL ===
      // Has generic children (Paragraph, Image, Table, etc.)
      case FluentCell cell:
        for (var i = 0; i < cell.children.length; i++) {
          final child = cell.children[i];
          final newPath = [...currentPath, i];
          if (child.id == targetId) return newPath;
          final found = _findNodePathRecursive(child, targetId, newPath);
          if (found != null) return found;
        }
        break;

      // === PARAGRAPH, LIST ITEM, LINK ===
      // All have fragments that can contain:
      // - Fragment (text)
      // - Link (from Paragraph)
      // - FluentList (sublist, from Paragraph/ListItem)
      // - Other inline nodes
        
      case Paragraph paragraph when node is! ListItem && node is! Link:
        // Generic Paragraph (not ListItem, not Link)
        for (var i = 0; i < paragraph.fragments.length; i++) {
          final child = paragraph.fragments[i];
          final newPath = [...currentPath, i];
          if (child.id == targetId) return newPath;
          final found = _findNodePathRecursive(child, targetId, newPath);
          if (found != null) return found;
        }
        break;
        
      case ListItem item:
        // ListItem is a generic container with children (Paragraph, Image, Table, etc.)
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
        
      // Other types (Fragment, FluentImage, etc.) - leaves, have no children
      default:
        break;
    }
    
    return null;
  }
  
  /// Compares two hierarchical paths (lexicographic)
  /// Returns -1 if a < b, 0 if a == b, 1 if a > b
  int _comparePaths(List<int> a, List<int> b) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    // If all elements up to minLen are equal, the shorter path comes first
    if (a.length < b.length) return -1;
    if (a.length > b.length) return 1;
    return 0;
  }
  
  /// True if target is between base and extent (inclusive)
  bool _isBetweenPaths(List<int> target, List<int> base, List<int> extent) {
    final compareBase = _comparePaths(target, base);
    final compareExtent = _comparePaths(target, extent);
    // target >= base AND target <= extent
    return (compareBase >= 0) && (compareExtent <= 0);
  }

  /// Determines if a node is selected (partially or completely)
  /// using hierarchical paths to correctly handle nested structure
  bool isNodeSelected(String nodeId) {
    if (!_selectionManager.hasSelection) return false;
    
    final state = _selectionManager.state;
    final anchor = state.anchor;
    final focus = state.focus;
    
    if (anchor == null || focus == null) return false;
    
    // Get node paths
    final nodePath = getNodePath(nodeId);
    final anchorPath = getNodePath(anchor.nodeId);
    final focusPath = getNodePath(focus.nodeId);
    
    if (nodePath == null || anchorPath == null || focusPath == null) return false;
    
    // Determine base and extent using paths
    final compare = _comparePaths(anchorPath, focusPath);
    final basePath = compare <= 0 ? anchorPath : focusPath;
    final extentPath = compare <= 0 ? focusPath : anchorPath;
    
    final result = _isBetweenPaths(nodePath, basePath, extentPath);
    
    return result;
  }
  
  /// For a given node, returns the selection range in terms of fragment/offset
  /// using hierarchical paths
  ({String startFrag, int startOff, String endFrag, int endOff})? getSelectionRangeForNode(String nodeId) {
    if (!_selectionManager.hasSelection) return null;
    if (!isNodeSelected(nodeId)) return null;
    
    final state = _selectionManager.state;
    final anchor = state.anchor!;
    final focus = state.focus!;
    
    final nodePath = getNodePath(nodeId);
    final anchorPath = getNodePath(anchor.nodeId);
    final focusPath = getNodePath(focus.nodeId);
    
    if (nodePath == null || anchorPath == null || focusPath == null) return null;
    
    // Determine base and extent
    final compare = _comparePaths(anchorPath, focusPath);
    final basePath = compare <= 0 ? anchorPath : focusPath;
    final extentPath = compare <= 0 ? focusPath : anchorPath;
    final base = compare <= 0 ? anchor : focus;
    final extent = compare <= 0 ? focus : anchor;
    
    final isBaseNode = _comparePaths(nodePath, basePath) == 0;
    final isExtentNode = _comparePaths(nodePath, extentPath) == 0;
    
    if (isBaseNode && isExtentNode) {
      // Selection entirely within this node
      return (
        startFrag: base.fragmentId,
        startOff: base.offset,
        endFrag: extent.fragmentId,
        endOff: extent.offset,
      );
    } else if (isBaseNode) {
      // Selection starts here and continues in other nodes
      return (
        startFrag: base.fragmentId,
        startOff: base.offset,
        endFrag: '',  // "" = end of node
        endOff: -1,
      );
    } else if (isExtentNode) {
      // Selection ends here, started in other nodes
      return (
        startFrag: '',  // "" = start of node
        startOff: 0,
        endFrag: extent.fragmentId,
        endOff: extent.offset,
      );
    } else {
      // Node completely selected (in the middle)
      return (
        startFrag: '',  // start
        startOff: 0,
        endFrag: '',    // end
        endOff: -1,
      );
    }
  }

  void updateContent() {
    notifyListeners();
  }

  /// Updates [pendingFontFamily] based on the font of the fragment under the
  /// collapsed cursor. Called after tap or cursor movements to
  /// keep the font selector aligned to the current position.
  void syncPendingFontWithCursor() {
    if (cursor.isCollapsed) {
      final fragNode = findById(_content, cursor.anchorId);
      final frag = fragNode is Fragment ? fragNode : null;
      pendingFontFamily = frag?.fontFamily ?? 'Arial';
      pendingFontSize = frag?.fontSize ?? 14.0;

      pendingColor = frag?.color;
      pendingHighlightColor = frag?.highlightColor;

      // Synchronize inline styles (bold, italic, underline)
      pendingStyles = List<String>.from(frag?.styles ?? []);

      // Synchronize alignment, indent and style from the containing paragraph
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
  String _previousText = '\u200B';
  bool _isResettingText = false;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _hiddenTextFieldFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contentStackKey = GlobalKey();
  final GlobalKey _scrollViewKey = GlobalKey();

  List<Widget> _buildNodes(FluentDocument doc) {
    return doc.content.nodes.map((node) {
      return buildFNodeWidget(node, doc);
    }).toList();
  }

  void _onDocumentChanged() {
    setState(() {});
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
    widget.document.mobileTextFieldFocusNode = _hiddenTextFieldFocusNode;
    // Platform.isAndroid and Platform.isIOS are not supported on web
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _previousText = '\u200B';
      _textEditingController.text = '\u200B';
      _textEditingController.addListener(_onMobileTextChanged);
    }
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
    // Save the initial state so undo always has a baseline to restore to.
    widget.document.saveState(description: 'Initial state', forceNewAction: true);
    _initSpellCheck();
    DocumentLanguageController.instance.currentLanguage
        .addListener(_onLanguageChanged);
  }

  void _initSpellCheck() async {
    await DocumentLanguageController.instance.initialize();
    // Sync the document language with the controller (resolves system locale).
    widget.document.documentLanguage =
        DocumentLanguageController.instance.current.code;
    final provider = widget.document.spellCheckProvider;
    if (provider != null) {
      await provider.initialize(widget.document.documentLanguage);
    }
  }

  void _onMobileTextChanged() {
    if (_isResettingText) return;

    final currentText = _textEditingController.text;

    // Backspace detected: text became empty or shorter than previous
    if (currentText.isEmpty || currentText.length < _previousText.length) {
      widget.document.saveState(description: 'Delete', forceNewAction: true);
      executeHandleBackspace(widget.document);
    } else if (currentText.length > _previousText.length) {
      // New character(s) inserted
      String newChars = currentText;
      if (_previousText == '\u200B' && currentText.startsWith('\u200B')) {
        newChars = currentText.substring(1);
      } else if (currentText.length > _previousText.length) {
        newChars = currentText.substring(_previousText.length);
      }

      if (newChars.isNotEmpty) {
        final lastChar = newChars[newChars.length - 1];
        if (!widget.document.cursor.isCollapsed) {
          widget.document.saveState(description: 'Replace selection');
          executeHandleReplaceSelection(lastChar, widget.document);
        } else {
          executeHandleInsertCharacter(lastChar, widget.document);
        }
      }
    }

    // Reset the text field to placeholder for next input
    _previousText = '\u200B';
    _isResettingText = true;
    _textEditingController.text = '\u200B';
    _isResettingText = false;
  }

  void _onLanguageChanged() {
    final newLang = DocumentLanguageController.instance.current.code;
    if (widget.document.documentLanguage != newLang) {
      widget.document.documentLanguage = newLang;
      final provider = widget.document.spellCheckProvider;
      provider?.reloadLanguage(newLang);
    }
  }

  /// Scrolls the document so the cursor caret is always visible in the
  /// viewport, with a small margin above and below.
  void _ensureCursorVisible() {
    if (!_scrollController.hasClients) return;

    final cursor = widget.document.cursor;
    if (cursor.anchorId.isEmpty) return;

    final caretStop = CaretStop(cursor.anchorId, cursor.anchorOffset);
    final caretGlobalY = widget.document.resolveCaretY(caretStop);
    if (caretGlobalY == 0.0) return;

    final scrollViewContext = _scrollViewKey.currentContext;
    if (scrollViewContext == null) return;
    final scrollViewBox = scrollViewContext.findRenderObject() as RenderBox?;
    if (scrollViewBox == null) return;

    final viewportTop = scrollViewBox.localToGlobal(Offset.zero).dy;
    final viewportBottom =
        viewportTop + _scrollController.position.viewportDimension;
    const margin = 40.0;

    if (caretGlobalY < viewportTop + margin) {
      final targetOffset = _scrollController.offset -
          (viewportTop + margin - caretGlobalY);
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    } else if (caretGlobalY > viewportBottom - margin) {
      final targetOffset = _scrollController.offset +
          (caretGlobalY - (viewportBottom - margin));
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
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
    widget.document.removeListener(_onDocumentChanged);
    DocumentLanguageController.instance.currentLanguage
        .removeListener(_onLanguageChanged);
    _scrollController.dispose();
    _focusNode.dispose();
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      _textEditingController.removeListener(_onMobileTextChanged);
    }
    _textEditingController.dispose();
    _hiddenTextFieldFocusNode.dispose();
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
                // Hidden TextField for mobile keyboard support (only on mobile)
                if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
                  IgnorePointer(
                    child: Opacity(
                      opacity: 0.0,
                      child: TextField(
                        controller: _textEditingController,
                        focusNode: _hiddenTextFieldFocusNode,
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  key: _scrollViewKey,
                  controller: _scrollController,
                  child: Stack(
                    key: _contentStackKey,
                    children: [
                      // Document area with right padding for sidebar.
                      // Wrapped in Focus so keyboard events go to the editor.
                      Focus(
                        focusNode: widget.document.editorFocusNode,
                        autofocus: true,
                        onKeyEvent: (node, event) {
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 20),
                                  FluentSelectableArea(
                                    document: widget.document,
                                    children: _buildNodes(widget.document),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Sidebar area (right side, scrolls with the document)
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
                ),
                // Stats panel in bottom-right corner (fixed, outside scroll view)
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
                // Toggle stats button (fixed, outside scroll view)
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
                // Sidebar collapse / expand toggle (fixed, outside scroll view)
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
