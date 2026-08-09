import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/plugins/builtin_plugin.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoid/nanoid.dart';

/// A minimal fixture plugin that registers a custom node type, a command,
/// a UI contribution, and a format. Used to validate the plugin registry
/// end-to-end without depending on built-in node internals.
class _FixturePlugin extends FluentEditorPlugin {
  @override
  String get id => 'test.fixture';

  @override
  String get version => '0.0.1';

  bool attached = false;
  bool detached = false;

  @override
  List<FluentNodeDefinition<FNode>> get nodes => [
    FluentNodeDefinition<FNode>(
      type: 'fixture.callout',
      nodeClass: _CalloutNode,
      decode: (json, _) => _CalloutNode(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
      ),
      create: (options) => _CalloutNode(
        text: options['text'] as String? ?? '',
      ),
      buildWidget: (node, document, _, _) => Text(
        (node as _CalloutNode).text,
        key: document.getKeyForNode(node.id),
      ),
    ),
  ];

  @override
  List<FluentCommand> get commands => [
    FluentCommand(
      id: 'fixture.insertCallout',
      label: 'Insert Callout',
      execute: (ctx) {
        ctx.document.saveState(description: 'Insert callout');
        final node = _CalloutNode(text: 'Hello from fixture');
        insertAfter(ctx.document.content, ctx.document.content.nodes.last, node);
        ctx.document.updateContent();
      },
      keyBindings: [
        FluentKeyBinding(key: LogicalKeyboardKey.keyF, control: true, alt: true),
      ],
    ),
  ];

  @override
  List<FluentUiContribution> get ui => [
    FluentUiContribution(
      id: 'fixture.toolbarButton',
      location: FluentPluginUiLocation.toolbar,
      builder: (_, _) => const SizedBox(width: 10, height: 10),
    ),
  ];

  @override
  List<FluentFormatContribution> get formats => [
    FluentFormatContribution(
      id: 'fixture.txt',
      label: 'Plain Text',
      extensions: ['txt'],
      kind: FluentPluginFormatKind.text,
      import: (payload, _) => Root(
        nodes: [Paragraph(text: payload.text ?? '')],
      ),
      export: (document) {
        final buffer = StringBuffer();
        for (final node in document.content.nodes) {
          if (node is Paragraph) buffer.writeln(node.text);
        }
        return FluentExportPayload.text(buffer.toString());
      },
    ),
  ];

  @override
  void attach(FluentPluginContext context) {
    attached = true;
  }

  @override
  void detach(FluentPluginContext context) {
    detached = true;
  }
}

/// Simple custom node for the fixture plugin.
class _CalloutNode extends FNode {
  final String text;

  _CalloutNode({String? id, this.text = ''}) : super(id ?? nanoid());

  @override
  Map<String, dynamic> toJson() => {
    'type': 'fixture.callout',
    'id': id,
    'text': text,
  };
}

void main() {
  group('FluentPluginRegistry', () {
    test('registers built-in nodes and resolves by type', () {
      final registry = createDefaultFluentPluginRegistry();
      expect(registry.nodeForType('paragraph'), isNotNull);
      expect(registry.nodeForType('link'), isNotNull);
      expect(registry.nodeForType('list'), isNotNull);
      expect(registry.nodeForType('table'), isNotNull);
      expect(registry.nodeForType('image'), isNotNull);
      expect(registry.nodeForType('hr'), isNotNull);
      expect(registry.nodeForType('fragment'), isNotNull);
    });

    test('decodes built-in nodes via registry', () {
      final registry = createDefaultFluentPluginRegistry();
      final node = registry.decodeNode({
        'type': 'paragraph',
        'id': 'test-1',
        'fragments': [
          {'type': 'fragment', 'id': 'frag-1', 'text': 'Hello', 'fontFamily': 'DejaVu Sans'},
        ],
      });
      expect(node, isA<Paragraph>());
      expect((node as Paragraph).fragments, hasLength(1));
    });

    test('creates nodes via registry', () {
      final registry = createDefaultFluentPluginRegistry();
      final node = registry.createNode('paragraph', {'text': 'Test'});
      expect(node, isA<Paragraph>());
    });

    test('throws on unknown node type', () {
      final registry = createDefaultFluentPluginRegistry();
      expect(
        () => registry.decodeNode({'type': 'nonexistent'}),
        throwsStateError,
      );
    });

    test('registers and looks up formats', () {
      final registry = createDefaultFluentPluginRegistry();
      expect(registry.format('fluent_editor.json'), isNotNull);
      expect(registry.format('fluent_editor.html'), isNotNull);
      expect(registry.formatForExtension('md'), isNotNull);
      expect(registry.formatForExtension('pdf'), isNotNull);
      expect(registry.formatForExtension('xyz'), isNull);
    });

    test('rejects duplicate plugin IDs', () {
      expect(
        () => FluentPluginRegistry([
          FluentBuiltInPlugin(),
          FluentBuiltInPlugin(),
        ]),
        throwsStateError,
      );
    });

    test('rejects plugin with wrong API version', () {
      final bad = _WrongApiPlugin();
      expect(
        () => FluentPluginRegistry([bad]),
        throwsStateError,
      );
    });
  });

  group('Fixture plugin integration', () {
    test('registers custom node type', () {
      final registry = createDefaultFluentPluginRegistry([_FixturePlugin()]);
      expect(registry.nodeForType('fixture.callout'), isNotNull);
    });

    test('decodes custom node via registry', () {
      final registry = createDefaultFluentPluginRegistry([_FixturePlugin()]);
      final node = registry.decodeNode({
        'type': 'fixture.callout',
        'id': 'c-1',
        'text': 'Test callout',
      });
      expect(node, isA<_CalloutNode>());
      expect((node as _CalloutNode).text, 'Test callout');
    });

    test('dispatches command via key event', () {
      final fixture = _FixturePlugin();
      final registry = createDefaultFluentPluginRegistry([fixture]);
      final document = FluentDocument(registry: registry);

      // Simulate Ctrl+Alt+F — test executeCommand directly
      // since HardwareKeyboard modifiers can't be set in unit tests.
      final executed = registry.executeCommand('fixture.insertCallout', document);
      expect(executed, isTrue);
      expect(document.content.nodes.any((n) => n is _CalloutNode), isTrue);
    });

    test('UI contributions are exposed at toolbar location', () {
      final registry = createDefaultFluentPluginRegistry([_FixturePlugin()]);
      final ui = registry.uiAt(FluentPluginUiLocation.toolbar).toList();
      expect(ui, hasLength(1));
      expect(ui.first.id, 'fixture.toolbarButton');
    });

    test('format contributions include fixture format', () {
      final registry = createDefaultFluentPluginRegistry([_FixturePlugin()]);
      expect(registry.format('fixture.txt'), isNotNull);
      expect(registry.formatForExtension('txt'), isNotNull);
    });

    test('attach/detach lifecycle is called', () {
      final fixture = _FixturePlugin();
      final registry = createDefaultFluentPluginRegistry([fixture]);
      final document = FluentDocument(registry: registry);

      expect(fixture.attached, isFalse);
      registry.attach(document);
      expect(fixture.attached, isTrue);

      registry.detach(document);
      expect(fixture.detached, isTrue);
    });

    test('FluentDocument.fromJson uses registry for decoding', () {
      final registry = createDefaultFluentPluginRegistry();
      final json = {
        'nodes': {
          'type': 'root',
          'id': 'root-1',
          'nodes': [
            {
              'type': 'paragraph',
              'id': 'p-1',
              'fragments': [
                {'type': 'fragment', 'id': 'f-1', 'text': 'Registry test', 'fontFamily': 'DejaVu Sans'},
              ],
            },
          ],
        },
        'settings': <String, dynamic>{},
      };
      final doc = FluentDocument.fromJson(json, registry: registry);
      expect(doc.content.nodes, hasLength(1));
      expect(doc.content.nodes.first, isA<Paragraph>());
    });
  });

  group('Registry-aware FNodeJsonConverter', () {
    test('falls back to hardcoded switch when no active registry', () {
      FNodeJsonConverter.activeRegistry = null;
      final node = const FNodeJsonConverter().fromJson({
        'type': 'paragraph',
        'id': 'p-fb',
        'fragments': [
          {'type': 'fragment', 'id': 'f-fb', 'text': 'Fallback', 'fontFamily': 'DejaVu Sans'},
        ],
      });
      expect(node, isA<Paragraph>());
    });

    test('uses registry when activeRegistry is set', () {
      final registry = createDefaultFluentPluginRegistry([_FixturePlugin()]);
      FNodeJsonConverter.activeRegistry = registry;
      try {
        final node = const FNodeJsonConverter().fromJson({
          'type': 'fixture.callout',
          'id': 'c-conv',
          'text': 'Via converter',
        });
        expect(node, isA<_CalloutNode>());
      } finally {
        FNodeJsonConverter.activeRegistry = null;
      }
    });
  });
}

/// Plugin with wrong API version for validation testing.
class _WrongApiPlugin extends FluentEditorPlugin {
  @override
  String get id => 'test.wrong_api';
  @override
  String get version => '0.0.1';
  @override
  int get apiVersion => 999;
}
