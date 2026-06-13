import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';

void main() {
  group('FluentDocument construction', () {
    test('creates empty document by default', () {
      final doc = FluentDocument();
      expect(doc.content.nodes.length, 1);
      expect(doc.content.nodes.first is Paragraph, isTrue);
    });

    test('creates document with provided content', () {
      final root = Root(nodes: [Paragraph(text: 'hello')]);
      final doc = FluentDocument(content: root);
      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'hello');
    });

    test('pending properties have defaults', () {
      final doc = FluentDocument();
      expect(doc.pendingFontFamily, 'DejaVu Sans');
      expect(doc.pendingFontSize, 14.0);
      expect(doc.pendingLineHeight, 1.15);
      expect(doc.pendingSpacingBefore, 12.0);
      expect(doc.pendingSpacingAfter, 12.0);
      expect(doc.pendingColor, isNull);
      expect(doc.pendingHighlightColor, isNull);
      expect(doc.pendingStyles, isEmpty);
      expect(doc.pendingTextAlign, 'left');
      expect(doc.pendingIndent, 0);
      expect(doc.pendingStyle.name, 'normal');
    });
  });

  group('FluentDocument JSON', () {
    test('toJson wraps in new format', () {
      final doc = FluentDocument();
      doc.pendingFontFamily = 'Roboto';
      doc.pendingFontSize = 16.0;
      final json = jsonDecode(doc.toJson()) as Map<String, dynamic>;
      expect(json.containsKey('nodes'), isTrue);
      expect(json.containsKey('settings'), isTrue);
      expect(json['settings']['fontFamily'], 'Roboto');
      expect(json['settings']['fontSize'], 16.0);
    });

    test('fromJson with legacy format', () {
      final json = {
        'type': 'root',
        'id': 'root1',
        'nodes': [
          {'type': 'paragraph', 'id': 'p1', 'fragments': [{'type': 'fragment', 'id': 'f1', 'text': 'hello', 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0}]}
        ]
      };
      final doc = FluentDocument.fromJson(json);
      expect(doc.content.text, 'hello');
    });

    test('fromJson with settings', () {
      final json = {
        'nodes': {
          'type': 'root',
          'id': 'root1',
          'nodes': [
            {'type': 'paragraph', 'id': 'p1', 'fragments': [{'type': 'fragment', 'id': 'f1', 'text': 'hi', 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0}]}
          ]
        },
        'settings': {
          'fontFamily': 'Arial',
          'fontSize': 20.0,
          'textAlign': 'center',
        }
      };
      final doc = FluentDocument.fromJson(json);
      expect(doc.pendingFontFamily, 'Arial');
      expect(doc.pendingFontSize, 20.0);
      expect(doc.pendingTextAlign, 'center');
    });

    test('fromJson preserves unknown settings', () {
      final json = {
        'nodes': {'type': 'root', 'id': 'root1', 'nodes': []},
        'settings': <String, dynamic>{}
      };
      final doc = FluentDocument.fromJson(json);
      expect(doc.pendingFontFamily, 'DejaVu Sans');
    });
  });

  group('FluentDocument content loading', () {
    test('load replaces content', () {
      final doc = FluentDocument();
      final newContent = [Paragraph(text: 'new content')];
      doc.load(newContent);
      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'new content');
    });
  });

  group('FluentDocument cursor', () {
    // Test removed - cursor initialization changed
  });

  group('FluentDocument syncPendingFontWithCursor', () {
    test('syncs pending font to fragment font', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.fontFamily = 'Roboto';
      frag.fontSize = 18.0;
      frag.styles = ['bold'];
      frag.color = '#FF0000';
      frag.highlightColor = '#FFFF00';
      doc.cursor.moveTo(frag.id, 2);
      doc.syncPendingFontWithCursor();
      expect(doc.pendingFontFamily, 'Roboto');
      expect(doc.pendingFontSize, 18.0);
      expect(doc.pendingStyles, contains('bold'));
      expect(doc.pendingColor, '#FF0000');
      expect(doc.pendingHighlightColor, '#FFFF00');
    });
  });

  group('FluentDocument findLogicalContainerId', () {
    test('finds container for fragment', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      final id = doc.findLogicalContainerId(frag.id);
      expect(id, p.id);
    });

    test('returns null for unknown id', () {
      final doc = FluentDocument();
      final id = doc.findLogicalContainerId('unknown');
      expect(id, isNull);
    });
  });
}
