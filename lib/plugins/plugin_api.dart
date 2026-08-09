import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/renderers/style_hook.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';
export 'package:fluent_editor/undo_redo/undo_redo_manager.dart';
import 'package:fluent_editor/widgets/editor/fluent_positioned_sidebar.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const int fluentPluginApiVersion = 1;

typedef FluentNodeDecoder = FNode Function(
  Map<String, dynamic> json,
  FluentPluginRegistry registry,
);
typedef FluentNodeFactory = FNode Function(Map<String, dynamic> options);
typedef FluentNodeWidgetBuilder = Widget Function(
  FNode node,
  FluentDocument document,
  int anchorOffset,
  int focusOffset,
);
typedef FluentCommandCallback = FutureOr<void> Function(
  FluentCommandContext context,
);
typedef FluentCommandPredicate = bool Function(FluentCommandContext context);

enum FluentPluginUiLocation {
  toolbar,
  fileMenu,
  editMenu,
  insertMenu,
  formatMenu,
  contextMenu,
  sidebar,
}

enum FluentPluginFormatKind { text, binary }

class FluentPluginDependency {
  final String pluginId;
  final String? minimumVersion;

  const FluentPluginDependency(this.pluginId, {this.minimumVersion});
}

class FluentCommandContext {
  final FluentDocument document;
  final BuildContext? buildContext;

  const FluentCommandContext(this.document, {this.buildContext});
}

class FluentKeyBinding {
  final LogicalKeyboardKey key;
  final bool control;
  final bool meta;
  final bool shift;
  final bool alt;
  final int priority;

  const FluentKeyBinding({
    required this.key,
    this.control = false,
    this.meta = false,
    this.shift = false,
    this.alt = false,
    this.priority = 0,
  });

  bool matches(KeyEvent event, HardwareKeyboard keyboard) {
    return event.logicalKey == key &&
        keyboard.isControlPressed == control &&
        keyboard.isMetaPressed == meta &&
        keyboard.isShiftPressed == shift &&
        keyboard.isAltPressed == alt;
  }

  String get signature =>
      '${key.keyId}:$control:$meta:$shift:$alt:$priority';
}

class FluentCommand {
  final String id;
  final String label;
  final FluentCommandCallback execute;
  final FluentCommandPredicate? canExecute;
  final List<FluentKeyBinding> keyBindings;
  final String? undoDescription;
  final bool forceNewUndoAction;

  const FluentCommand({
    required this.id,
    required this.label,
    required this.execute,
    this.canExecute,
    this.keyBindings = const [],
    this.undoDescription,
    this.forceNewUndoAction = false,
  });
}

class FluentUiContribution {
  final String id;
  final FluentPluginUiLocation location;
  final int order;
  final Widget Function(BuildContext context, FluentDocument document) builder;
  final bool Function(FluentDocument document)? visible;

  const FluentUiContribution({
    required this.id,
    required this.location,
    required this.builder,
    this.order = 0,
    this.visible,
  });
}

class FluentImportPayload {
  final String? text;
  final Uint8List? bytes;

  const FluentImportPayload.text(this.text) : bytes = null;
  const FluentImportPayload.binary(this.bytes) : text = null;
}

class FluentExportPayload {
  final String? text;
  final Uint8List? bytes;

  const FluentExportPayload.text(this.text) : bytes = null;
  const FluentExportPayload.binary(this.bytes) : text = null;
}

class FluentFormatContribution {
  final String id;
  final String label;
  final List<String> extensions;
  final List<String> mimeTypes;
  final FluentPluginFormatKind kind;
  final FutureOr<Root> Function(
    FluentImportPayload payload,
    FluentPluginRegistry registry,
  )? import;
  final FutureOr<FluentExportPayload> Function(FluentDocument document)? export;

  const FluentFormatContribution({
    required this.id,
    required this.label,
    required this.extensions,
    this.mimeTypes = const [],
    this.kind = FluentPluginFormatKind.text,
    this.import,
    this.export,
  });
}

class FluentNodeDefinition<T extends FNode> {
  final String type;
  final Type nodeClass;
  final FluentNodeDecoder decode;
  final FluentNodeFactory create;
  final FluentNodeWidgetBuilder buildWidget;
  final List<FNode> Function(T node) children;
  final List<FNode>? Function(T node) mutableChildren;
  final bool inline;
  final bool atomic;
  final Map<String, Object? Function(T node)> formatProjections;

  const FluentNodeDefinition({
    required this.type,
    required this.nodeClass,
    required this.decode,
    required this.create,
    required this.buildWidget,
    this.children = _noChildren,
    this.mutableChildren = _noMutableChildren,
    this.inline = false,
    this.atomic = false,
    this.formatProjections = const {},
  });

  static List<FNode> _noChildren(FNode _) => const [];
  static List<FNode>? _noMutableChildren(FNode _) => null;
}

abstract class FluentEditorPlugin {
  String get id;
  String get version;
  int get apiVersion => fluentPluginApiVersion;
  List<FluentPluginDependency> get dependencies => const [];
  List<FluentNodeDefinition<FNode>> get nodes => const [];
  List<FluentCommand> get commands => const [];
  List<FluentUiContribution> get ui => const [];
  List<FluentFormatContribution> get formats => const [];
  RenderStyleHook? get styleHook => null;

  /// Returns sidebar item entries (cards) contributed by this plugin.
  /// Libraries define how their cards appear by returning [FluentSidebarItem]s.
  List<FluentSidebarItem> buildSidebarItems(
    BuildContext context,
    FluentDocument document,
  ) =>
      const [];

  /// Returns true if this plugin contributes to the document sidebar.
  bool get hasSidebar => false;

  void attach(FluentPluginContext context) {}
  void detach(FluentPluginContext context) {}

  /// Intercepts character insertion. Return true if handled.
  bool onInsertCharacter(String character, FluentDocument document) => false;

  /// Intercepts inserting text (single character or multi-character string from IME/paste). Return true if handled.
  bool onInsertText(String text, FluentDocument document) => false;

  /// Intercepts inserting a node (e.g. hr, image, list, table). Return true if handled.
  bool onInsertNode(
    FluentDocument document,
    String nodeType,
    Map<String, dynamic> options,
  ) =>
      false;

  /// Intercepts committing IME composition/preedit text. Return true if handled.
  bool onImeCompositionCommit(String text, FluentDocument document) => false;

  /// Intercepts Backspace key. Return true if handled.
  bool onBackspace(
    FluentDocument document, {
    bool ctrl = false,
    bool lineStart = false,
  }) =>
      false;

  /// Intercepts Delete key. Return true if handled.
  bool onDelete(FluentDocument document, {bool ctrl = false}) => false;

  /// Intercepts deleting a node (e.g. image, HR, table). Return true if handled.
  bool onDeleteNode(FluentDocument document, FNode node) => false;

  /// Intercepts Enter key (line/item split). Return true if handled.
  bool onEnter(FluentDocument document) => false;

  /// Intercepts Tab/Shift+Tab keys (indent/outdent). Return true if handled.
  bool onTab(FluentDocument document, {required bool isShiftPressed}) => false;

  /// Intercepts replacing active selection with text. Return true if handled.
  bool onReplaceSelection(String character, FluentDocument document) => false;

  /// Intercepts inserting a table row. Return true if handled.
  bool onInsertTableRow(FluentDocument document, FluentTable table, int index) => false;

  /// Intercepts deleting a table row. Return true if handled.
  bool onDeleteTableRow(FluentDocument document, FluentTable table, int index) => false;

  /// Intercepts inserting a table column. Return true if handled.
  bool onInsertTableColumn(FluentDocument document, FluentTable table, int index) => false;

  /// Intercepts deleting a table column. Return true if handled.
  bool onDeleteTableColumn(FluentDocument document, FluentTable table, int index) => false;

  /// Intercepts increasing table cell rowspan. Return true if handled.
  bool onIncreaseTableRowspan(FluentDocument document, FluentTable table, FluentCell cell) => false;

  /// Intercepts decreasing table cell rowspan. Return true if handled.
  bool onDecreaseTableRowspan(FluentDocument document, FluentTable table, FluentCell cell) => false;

  /// Intercepts increasing table cell colspan. Return true if handled.
  bool onIncreaseTableColspan(FluentDocument document, FluentTable table, FluentCell cell) => false;

  /// Intercepts decreasing table cell colspan. Return true if handled.
  bool onDecreaseTableColspan(FluentDocument document, FluentTable table, FluentCell cell) => false;

  /// Intercepts an inline style mutation on a fragment. Return the modified/new fragment if handled, null otherwise.
  Fragment? onStyleMutation(FluentDocument document, Fragment leaf, void Function(Fragment) mutator) => null;

  /// Intercepts an inline style mutation on a list of fragments. Return the modified/new fragments if handled, null otherwise.
  List<Fragment>? onLeavesStyleMutation(FluentDocument document, List<Fragment> leaves, void Function(Fragment) mutator) => null;

  /// Intercepts a paragraph mutation. Return true if handled, false otherwise.
  bool onParagraphMutation(FluentDocument document, Paragraph paragraph, void Function(Paragraph) mutator) => false;

  /// Called whenever document text is mutated.
  void onTextMutation(String paragraphId, int fromOffset, int delta) {}

  /// Called when a saveState operation begins for the document.
  void onSaveState(FluentDocument document, String description) {}

  /// Called when a saveState operation is committed for the document.
  void onCommitSaveState(
    FluentDocument document, {
    SaveStateResult result = SaveStateResult.created,
  }) {}

  /// Called after an undo operation restores the document state.
  void onUndo(FluentDocument document) {}

  /// Called after a redo operation restores the document state.
  void onRedo(FluentDocument document) {}

  /// Called when a table column is resized. Return true if handled.
  bool onColumnResize(
    FluentDocument document,
    FluentTable table,
    int colIdx,
    double oldWidth,
    double newWidth,
  ) =>
      false;

  /// Called when a table row is resized. Return true if handled.
  bool onRowResize(
    FluentDocument document,
    FluentTable table,
    FluentRow row,
    double oldHeight,
    double newHeight,
  ) =>
      false;

  /// Returns true if the column at [colIdx] in [table] has a pending resize suggestion.
  bool isColumnResized(FluentDocument document, FluentTable table, int colIdx) => false;

  /// Returns true if the row [row] in [table] has a pending resize suggestion.
  bool isRowResized(FluentDocument document, FluentTable table, FluentRow row) => false;

  /// Returns true if style formatting actions (bold, italic, color, font size, etc.)
  /// should be disabled on [document].
  bool isFormattingDisabled(FluentDocument document) => false;

  /// Returns true if this plugin is currently operating in suggestion/review mode.
  bool get isSuggestionMode => false;
}

class FluentPluginContext {
  final FluentDocument document;
  final FluentPluginRegistry registry;

  const FluentPluginContext(this.document, this.registry);
}

class FluentPluginRegistry {
  final List<FluentEditorPlugin> plugins;
  final Map<String, FluentNodeDefinition<FNode>> _nodes;
  final Map<Type, FluentNodeDefinition<FNode>> _nodeClasses;
  final Map<String, FluentCommand> _commands;
  final Map<String, FluentFormatContribution> _formats;
  final List<FluentUiContribution> _ui;
  late final List<RenderStyleHook> _styleHooksCache;

  FluentPluginRegistry(Iterable<FluentEditorPlugin> source)
      : plugins = _sortAndValidatePlugins(source.toList()),
        _nodes = {},
        _nodeClasses = {},
        _commands = {},
        _formats = {},
        _ui = [] {
    for (final plugin in plugins) {
      if (plugin.apiVersion != fluentPluginApiVersion) {
        throw StateError(
          'Plugin ${plugin.id} requires API ${plugin.apiVersion}, supported API is $fluentPluginApiVersion',
        );
      }
      for (final node in plugin.nodes) {
        _putUnique(_nodes, node.type, node, 'node type', plugin.id);
        _putUnique(_nodeClasses, node.nodeClass, node, 'node class', plugin.id);
      }
      for (final command in plugin.commands) {
        _putUnique(_commands, command.id, command, 'command', plugin.id);
      }
      for (final format in plugin.formats) {
        _putUnique(_formats, format.id, format, 'format', plugin.id);
      }
      for (final contribution in plugin.ui) {
        if (_ui.any((item) => item.id == contribution.id)) {
          throw StateError(
            'Duplicate UI contribution ${contribution.id} from plugin ${plugin.id}',
          );
        }
        _ui.add(contribution);
      }
    }
    _validateKeyBindings();
    _ui.sort((a, b) {
      final location = a.location.index.compareTo(b.location.index);
      return location != 0 ? location : a.order.compareTo(b.order);
    });
    _styleHooksCache = plugins.map((p) => p.styleHook).whereType<RenderStyleHook>().toList();
  }

  FluentNodeDefinition<FNode>? nodeForType(String type) => _nodes[type];

  FluentNodeDefinition<FNode>? nodeFor(FNode node) =>
      _nodeClasses[node.runtimeType] ?? _nodes[node.toJson()['type']];

  FluentCommand? command(String id) => _commands[id];

  FluentFormatContribution? format(String id) => _formats[id];

  List<RenderStyleHook> get styleHooks => _styleHooksCache;

  /// Returns true if any registered plugin supports sidebar items.
  bool get hasSidebarPlugins => plugins.any((p) => p.hasSidebar);

  FluentFormatContribution? formatForExtension(String ext) {
    final lower = ext.toLowerCase();
    for (final f in _formats.values) {
      if (f.extensions.any((e) => e.toLowerCase() == lower)) return f;
    }
    return null;
  }

  Iterable<FluentFormatContribution> get formats => _formats.values;

  Iterable<FluentCommand> get commands => _commands.values;

  Iterable<FluentUiContribution> uiAt(FluentPluginUiLocation location) =>
      _ui.where((item) => item.location == location);

  /// Collects all sidebar items contributed across registered plugins.
  List<FluentSidebarItem> buildSidebarItems(
    BuildContext context,
    FluentDocument document,
  ) {
    final items = <FluentSidebarItem>[];
    for (final plugin in plugins) {
      items.addAll(plugin.buildSidebarItems(context, document));
    }
    return items;
  }

  FNode decodeNode(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final definition = type == null ? null : _nodes[type];
    if (definition == null) {
      throw StateError('No plugin registered for node type "$type"');
    }
    return definition.decode(json, this);
  }

  FNode createNode(String type, [Map<String, dynamic> options = const {}]) {
    final definition = _nodes[type];
    if (definition == null) {
      throw StateError('No plugin registered for node type "$type"');
    }
    return definition.create(options);
  }

  bool dispatchKeyEvent(
    KeyEvent event,
    FluentDocument document, {
    BuildContext? buildContext,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final matches = <(FluentKeyBinding, FluentCommand)>[];
    for (final command in _commands.values) {
      for (final binding in command.keyBindings) {
        if (binding.matches(event, keyboard)) matches.add((binding, command));
      }
    }
    if (matches.isEmpty) return false;
    matches.sort((a, b) => b.$1.priority.compareTo(a.$1.priority));
    final command = matches.first.$2;
    return executeCommand(command.id, document, buildContext: buildContext);
  }

  bool executeCommand(
    String id,
    FluentDocument document, {
    BuildContext? buildContext,
  }) {
    final command = _commands[id];
    if (command == null) return false;
    final context = FluentCommandContext(document, buildContext: buildContext);
    if (command.canExecute?.call(context) == false) return false;
    if (command.undoDescription != null) {
      document.saveState(
        description: command.undoDescription!,
        forceNewAction: command.forceNewUndoAction,
      );
    }
    command.execute(context);
    return true;
  }

  void attach(FluentDocument document) {
    final context = FluentPluginContext(document, this);
    for (final plugin in plugins) {
      plugin.attach(context);
    }
  }

  void detach(FluentDocument document) {
    final context = FluentPluginContext(document, this);
    for (final plugin in plugins.reversed) {
      plugin.detach(context);
    }
  }

  bool dispatchInsertCharacter(String character, FluentDocument document) {
    for (final plugin in plugins) {
      if (plugin.onInsertCharacter(character, document)) return true;
    }
    return false;
  }

  bool dispatchInsertText(String text, FluentDocument document) {
    for (final plugin in plugins) {
      if (plugin.onInsertText(text, document)) return true;
    }
    return false;
  }

  bool dispatchInsertNode(
    FluentDocument document,
    String nodeType,
    Map<String, dynamic> options,
  ) {
    for (final plugin in plugins) {
      if (plugin.onInsertNode(document, nodeType, options)) return true;
    }
    return false;
  }

  Fragment? dispatchStyleMutation(FluentDocument document, Fragment leaf, void Function(Fragment) mutator) {
    for (final plugin in plugins) {
      final res = plugin.onStyleMutation(document, leaf, mutator);
      if (res != null) return res;
    }
    return null;
  }

  List<Fragment>? dispatchLeavesStyleMutation(FluentDocument document, List<Fragment> leaves, void Function(Fragment) mutator) {
    for (final plugin in plugins) {
      final res = plugin.onLeavesStyleMutation(document, leaves, mutator);
      if (res != null) return res;
    }
    return null;
  }

  bool dispatchParagraphMutation(FluentDocument document, Paragraph paragraph, void Function(Paragraph) mutator) {
    for (final plugin in plugins) {
      if (plugin.onParagraphMutation(document, paragraph, mutator)) return true;
    }
    return false;
  }

  bool dispatchImeCompositionCommit(String text, FluentDocument document) {
    for (final plugin in plugins) {
      if (plugin.onImeCompositionCommit(text, document)) return true;
    }
    return false;
  }

  bool dispatchEnter(FluentDocument document) {
    for (final plugin in plugins) {
      if (plugin.onEnter(document)) return true;
    }
    return false;
  }

  bool dispatchTab(FluentDocument document, {required bool isShiftPressed}) {
    for (final plugin in plugins) {
      if (plugin.onTab(document, isShiftPressed: isShiftPressed)) return true;
    }
    return false;
  }

  bool dispatchColumnResize(
    FluentDocument document,
    FluentTable table,
    int colIdx,
    double oldWidth,
    double newWidth,
  ) {
    for (final plugin in plugins) {
      if (plugin.onColumnResize(document, table, colIdx, oldWidth, newWidth)) {
        return true;
      }
    }
    return false;
  }

  bool dispatchRowResize(
    FluentDocument document,
    FluentTable table,
    FluentRow row,
    double oldHeight,
    double newHeight,
  ) {
    for (final plugin in plugins) {
      if (plugin.onRowResize(document, table, row, oldHeight, newHeight)) {
        return true;
      }
    }
    return false;
  }

  bool isColumnResized(FluentDocument document, FluentTable table, int colIdx) {
    for (final plugin in plugins) {
      if (plugin.isColumnResized(document, table, colIdx)) return true;
    }
    return false;
  }

  bool isRowResized(FluentDocument document, FluentTable table, FluentRow row) {
    for (final plugin in plugins) {
      if (plugin.isRowResized(document, table, row)) return true;
    }
    return false;
  }

  /// Returns true if any registered plugin requires formatting/style actions to be disabled.
  bool isFormattingDisabled(FluentDocument document) {
    for (final plugin in plugins) {
      if (plugin.isFormattingDisabled(document)) return true;
    }
    return false;
  }

  /// Returns true if any registered plugin is currently in suggestion/review mode.
  bool get isSuggestionMode {
    for (final plugin in plugins) {
      if (plugin.isSuggestionMode) return true;
    }
    return false;
  }

  bool dispatchBackspace(
    FluentDocument document, {
    bool ctrl = false,
    bool lineStart = false,
  }) {
    for (final plugin in plugins) {
      if (plugin.onBackspace(document, ctrl: ctrl, lineStart: lineStart)) {
        return true;
      }
    }
    return false;
  }

  bool dispatchDelete(FluentDocument document, {bool ctrl = false}) {
    for (final plugin in plugins) {
      if (plugin.onDelete(document, ctrl: ctrl)) return true;
    }
    return false;
  }

  bool dispatchDeleteNode(FluentDocument document, FNode node) {
    for (final plugin in plugins) {
      if (plugin.onDeleteNode(document, node)) return true;
    }
    return false;
  }

  bool dispatchReplaceSelection(String character, FluentDocument document) {
    for (final plugin in plugins) {
      if (plugin.onReplaceSelection(character, document)) return true;
    }
    return false;
  }

  void dispatchTextMutation(String paragraphId, int fromOffset, int delta) {
    for (final plugin in plugins) {
      plugin.onTextMutation(paragraphId, fromOffset, delta);
    }
  }

  void dispatchSaveState(FluentDocument document, String description) {
    for (final plugin in plugins) {
      plugin.onSaveState(document, description);
    }
  }

  void dispatchCommitSaveState(
    FluentDocument document, {
    SaveStateResult result = SaveStateResult.created,
  }) {
    for (final plugin in plugins) {
      plugin.onCommitSaveState(document, result: result);
    }
  }

  void dispatchUndo(FluentDocument document) {
    for (final plugin in plugins) {
      plugin.onUndo(document);
    }
  }

  void dispatchRedo(FluentDocument document) {
    for (final plugin in plugins) {
      plugin.onRedo(document);
    }
  }

  static void _putUnique<K, V>(
    Map<K, V> target,
    K key,
    V value,
    String kind,
    String pluginId,
  ) {
    if (target.containsKey(key)) {
      throw StateError('Duplicate $kind "$key" from plugin $pluginId');
    }
    target[key] = value;
  }

  void _validateKeyBindings() {
    final seen = <String, String>{};
    for (final command in _commands.values) {
      for (final binding in command.keyBindings) {
        final previous = seen[binding.signature];
        if (previous != null) {
          throw StateError(
            'Shortcut conflict between commands $previous and ${command.id}',
          );
        }
        seen[binding.signature] = command.id;
      }
    }
  }

  static List<FluentEditorPlugin> _sortAndValidatePlugins(
    List<FluentEditorPlugin> plugins,
  ) {
    final byId = <String, FluentEditorPlugin>{};
    for (final plugin in plugins) {
      if (plugin.id.isEmpty) throw StateError('Plugin ID cannot be empty');
      if (byId.containsKey(plugin.id)) {
        throw StateError('Duplicate plugin ID ${plugin.id}');
      }
      byId[plugin.id] = plugin;
    }
    final result = <FluentEditorPlugin>[];
    final visiting = <String>{};
    final visited = <String>{};

    void visit(FluentEditorPlugin plugin) {
      if (visited.contains(plugin.id)) return;
      if (!visiting.add(plugin.id)) {
        throw StateError('Circular plugin dependency involving ${plugin.id}');
      }
      for (final dependency in plugin.dependencies) {
        final requiredPlugin = byId[dependency.pluginId];
        if (requiredPlugin == null) {
          throw StateError(
            'Plugin ${plugin.id} requires missing plugin ${dependency.pluginId}',
          );
        }
        visit(requiredPlugin);
      }
      visiting.remove(plugin.id);
      visited.add(plugin.id);
      result.add(plugin);
    }

    for (final plugin in plugins) {
      visit(plugin);
    }
    return List.unmodifiable(result);
  }
}
