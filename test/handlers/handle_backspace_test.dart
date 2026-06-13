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
  });
}
