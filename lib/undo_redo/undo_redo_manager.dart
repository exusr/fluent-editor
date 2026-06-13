import 'dart:async';
import 'dart:convert';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart' as factories;
import 'package:fluent_editor/styles.dart';

/// Represents a document state that can be undone/redone
class DocumentState {
  final String contentJson;
  final String cursorId;
  final int cursorOffset;
  final String? selectionAnchorId;
  final int? selectionAnchorOffset;
  final String? selectionFocusId;
  final int? selectionFocusOffset;
  final DateTime timestamp;
  final String description;

  // Pending formatting state (needed for undo/redo of clear formatting, etc.)
  final String pendingFontFamily;
  final double pendingFontSize;
  final String? pendingColor;
  final String? pendingHighlightColor;
  final List<String> pendingStyles;
  final String pendingTextAlign;
  final int pendingIndent;
  final ParagraphStyle pendingStyle;

  DocumentState({
    required this.contentJson,
    required this.cursorId,
    required this.cursorOffset,
    this.selectionAnchorId,
    this.selectionAnchorOffset,
    this.selectionFocusId,
    this.selectionFocusOffset,
    required this.timestamp,
    required this.description,
    required this.pendingFontFamily,
    required this.pendingFontSize,
    this.pendingColor,
    this.pendingHighlightColor,
    required this.pendingStyles,
    required this.pendingTextAlign,
    required this.pendingIndent,
    required this.pendingStyle,
  });

  /// Creates a state from the current document
  factory DocumentState.fromDocument(
    FluentDocument document, {
    String description = 'Document change',
  }) {
    final cursor = document.cursor;
    return DocumentState(
      contentJson: document.toJson(),
      cursorId: cursor.anchorId,
      cursorOffset: cursor.anchorOffset,
      selectionAnchorId: cursor.isCollapsed ? null : cursor.anchorId,
      selectionAnchorOffset: cursor.isCollapsed ? null : cursor.anchorOffset,
      selectionFocusId: cursor.isCollapsed ? null : cursor.focusId,
      selectionFocusOffset: cursor.isCollapsed ? null : cursor.focusOffset,
      timestamp: DateTime.now(),
      description: description,
      pendingFontFamily: document.pendingFontFamily,
      pendingFontSize: document.pendingFontSize,
      pendingColor: document.pendingColor,
      pendingHighlightColor: document.pendingHighlightColor,
      pendingStyles: List<String>.from(document.pendingStyles),
      pendingTextAlign: document.pendingTextAlign,
      pendingIndent: document.pendingIndent,
      pendingStyle: document.pendingStyle,
    );
  }

  /// Restores this state to the document
  void restoreToDocument(FluentDocument document) {
    // Parse the JSON content and restore it
    final contentMap = jsonDecode(contentJson) as Map<String, dynamic>;
    // contentJson comes from FluentDocument.toJson() which wraps the Root
    // in a Map with 'nodes' and 'settings' keys.
    final rootJson = contentMap['nodes'] as Map<String, dynamic>;
    final newContent = factories.Root.fromJson(rootJson);
    
    // Use the load method to replace the content
    document.load(newContent.nodes);
    
    // Restore cursor position
    document.cursor.moveTo(cursorId, cursorOffset);
    
    // Restore selection if exists using proper Cursor API
    if (!isCollapsedSelection) {
      // First move to anchor position
      document.cursor.moveTo(selectionAnchorId!, selectionAnchorOffset!);
      // Then extend selection to focus position
      document.cursor.focusTo(selectionFocusId!, selectionFocusOffset!);
    }

    // Restore pending formatting state
    document.pendingFontFamily = pendingFontFamily;
    document.pendingFontSize = pendingFontSize;
    document.pendingColor = pendingColor;
    document.pendingHighlightColor = pendingHighlightColor;
    document.pendingStyles = List<String>.from(pendingStyles);
    document.pendingTextAlign = pendingTextAlign;
    document.pendingIndent = pendingIndent;
    document.pendingStyle = pendingStyle;

    document.updateContent();
  }

  bool get isCollapsedSelection => 
      selectionAnchorId == null || selectionFocusId == null;

  @override
  String toString() {
    return 'DocumentState($description, ${timestamp.toIso8601String()})';
  }
}

/// Undo/Redo system manager
class UndoRedoManager {
  static const int _maxUndoStates = 100;
  static const Duration _groupingTimeout = Duration(milliseconds: 300);

  final List<DocumentState> _undoStack = [];
  final List<DocumentState> _redoStack = [];
  
  Timer? _groupingTimer;
  String? _currentGroupDescription;
  DateTime? _lastActionTime;
  
  bool _isRestoringState = false;

  /// Checks if undo is possible
  bool get canUndo => _undoStack.isNotEmpty;

  /// Checks if redo is possible
  bool get canRedo => _redoStack.isNotEmpty;

  /// Number of states available for undo
  int get undoCount => _undoStack.length;

  /// Number of states available for redo
  int get redoCount => _redoStack.length;

  /// Saves the current document state
  void saveState(
    FluentDocument document, {
    String description = 'Document change',
    bool forceNewAction = false,
  }) {
    if (_isRestoringState) return; // Don't save during restore

    final now = DateTime.now();
    final newState = DocumentState.fromDocument(document, description: description);

    // Intelligent grouping management
    if (!forceNewAction &&
        _currentGroupDescription != null &&
        description == _currentGroupDescription &&
        _lastActionTime != null &&
        now.difference(_lastActionTime!) <= _groupingTimeout) {

      // Same group: replace the last state
      if (_undoStack.isNotEmpty) {
        _undoStack.last = newState;
      } else {
        _undoStack.add(newState);
      }

      // Reset the timer
      _groupingTimer?.cancel();
      _groupingTimer = Timer(_groupingTimeout, () {
        _currentGroupDescription = null;
        _lastActionTime = null;
      });
    } else {
      // New group: add to stack and clear redo
      _undoStack.add(newState);
      _redoStack.clear();

      _currentGroupDescription = description;
      _lastActionTime = now;

      // Reset the timer
      _groupingTimer?.cancel();
      _groupingTimer = Timer(_groupingTimeout, () {
        _currentGroupDescription = null;
        _lastActionTime = null;
      });
    }

    // Maintain memory limit
    _enforceMemoryLimit();
  }

  /// Executes the undo
  bool undo(FluentDocument document) {
    if (!canUndo) return false;

    final currentState = DocumentState.fromDocument(document, description: 'Before undo');
    _redoStack.add(currentState);

    final stateToRestore = _undoStack.last;
    _undoStack.removeLast();
    _isRestoringState = true;
    try {
      stateToRestore.restoreToDocument(document);
    } finally {
      _isRestoringState = false;
    }

    // Reset grouping after an undo action
    _resetGrouping();

    return true;
  }

  /// Executes the redo
  bool redo(FluentDocument document) {
    if (!canRedo) return false;

    final currentState = DocumentState.fromDocument(document, description: 'Before redo');
    _undoStack.add(currentState);

    final stateToRestore = _redoStack.removeLast();
    _isRestoringState = true;
    try {
      stateToRestore.restoreToDocument(document);
    } finally {
      _isRestoringState = false;
    }

    // Reset grouping after a redo action
    _resetGrouping();

    return true;
  }

  /// Clears both stacks
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _resetGrouping();
  }

  /// Forces the creation of a new action (not grouped)
  void forceNewAction(FluentDocument document, {String description = 'New action'}) {
    saveState(document, description: description, forceNewAction: true);
  }

  /// Returns the description of the last undo action
  String? get lastUndoDescription => _undoStack.isNotEmpty ? _undoStack.last.description : null;

  /// Returns the description of the last redo action
  String? get lastRedoDescription => _redoStack.isNotEmpty ? _redoStack.last.description : null;

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
  }

  /// Dispose of the manager
  void dispose() {
    _groupingTimer?.cancel();
    clear();
  }
}
