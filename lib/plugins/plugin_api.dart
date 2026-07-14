import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
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
  void attach(FluentPluginContext context) {}
  void detach(FluentPluginContext context) {}
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
  }

  FluentNodeDefinition<FNode>? nodeForType(String type) => _nodes[type];

  FluentNodeDefinition<FNode>? nodeFor(FNode node) =>
      _nodeClasses[node.runtimeType] ?? _nodes[node.toJson()['type']];

  FluentCommand? command(String id) => _commands[id];

  FluentFormatContribution? format(String id) => _formats[id];

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
