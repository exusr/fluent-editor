import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';

void main() {
  late FluentDocument document;

  setUp(() {
    document = FluentDocument();
    document.eventHandler.document = document;
  });

  group('executeHandleBackspace', () {
    test('deletes previous character in fragment', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'hello';
      document.cursor.moveTo(frag.id, 5);
      executeHandleBackspace(document);
      expect(frag.text, 'hell');
      expect(document.cursor.anchorOffset, 4);
    });

    test('deletes at beginning of paragraph merges with previous', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: ' world');
      document = FluentDocument(content: Root(nodes: [p1, p2]));
      document.eventHandler.document = document;
      final frag2 = p2.fragments.first as Fragment;
      document.cursor.moveTo(frag2.id, 0);
      executeHandleBackspace(document);
      expect(document.content.nodes.length, 1);
      expect(document.content.text, 'hello world');
    });

    test('returns true on success', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'x';
      document.cursor.moveTo(frag.id, 1);
      final result = executeHandleBackspace(document);
      expect(result, isTrue);
    });

    test('removes HorizontalRule when cursor on it', () {
      final hr = HorizontalRule();
      document = FluentDocument(content: Root(nodes: [hr]));
      document.eventHandler.document = document;
      document.cursor.moveTo(hr.id, 0);
      executeHandleBackspace(document);
      expect(document.content.nodes.whereType<HorizontalRule>(), isEmpty);
    });

    test('sole empty fragment at paragraph start merges with previous', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: 'world');
      document = FluentDocument(content: Root(nodes: [p1, p2]));
      document.eventHandler.document = document;
      final frag2 = p2.fragments.first as Fragment;
      // Empty the fragment and leave cursor at offset 0
      frag2.text = '';
      document.cursor.moveTo(frag2.id, 0);
      executeHandleBackspace(document);
      expect(document.content.nodes.length, 1);
      expect(document.content.text, 'hello');
    });

    test('backspace at fragment start on non-empty fragment merges with previous', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: 'world');
      document = FluentDocument(content: Root(nodes: [p1, p2]));
      document.eventHandler.document = document;
      final frag2 = p2.fragments.first as Fragment;
      document.cursor.moveTo(frag2.id, 0);
      executeHandleBackspace(document);
      expect(document.content.nodes.length, 1);
      expect(document.content.text, 'helloworld');
    });

    test('backspace emptying fragment next to image falls back to valid caret stop', () {
      final image = FluentImage('test.png');
      final p = Paragraph(text: 'hi');
      document = FluentDocument(content: Root(nodes: [p]));
      document.eventHandler.document = document;
      p.fragments.add(image);
      final frag = p.fragments.first as Fragment;
      document.cursor.moveTo(frag.id, 2);
      executeHandleBackspace(document); // delete 'i'
      executeHandleBackspace(document); // delete 'h', fragment becomes empty
      // The empty fragment should be removed and cursor should not point to it
      expect(document.nodeById(frag.id), isNull);
      // Cursor should land on a valid existing node (the image via fallback)
      final currentNode = document.nodeById(document.cursor.anchorId);
      expect(currentNode, isNotNull);
    });
  });
}
