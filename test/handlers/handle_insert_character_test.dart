import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_insert_character.dart';

void main() {
  late FluentDocument document;

  setUp(() {
    document = FluentDocument();
    document.eventHandler.document = document;
  });

  group('executeHandleInsertCharacter', () {
    test('inserts character in empty paragraph', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      document.cursor.moveTo(frag.id, 0);
      executeHandleInsertCharacter('x', document);
      expect(frag.text, 'x');
      expect(document.cursor.anchorOffset, 1);
    });

    test('inserts character in middle of text', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'hello';
      document.cursor.moveTo(frag.id, 2);
      executeHandleInsertCharacter('X', document);
      expect(frag.text, 'heXllo');
      expect(document.cursor.anchorOffset, 3);
    });

    test('inserts character at end of text', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'hello';
      document.cursor.moveTo(frag.id, 5);
      executeHandleInsertCharacter('!', document);
      expect(frag.text, 'hello!');
    });

    test('applies pending font when different', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'hello';
      frag.fontFamily = 'DejaVu Sans';
      document.pendingFontFamily = 'Roboto';
      document.cursor.moveTo(frag.id, 2);
      executeHandleInsertCharacter('X', document);
      // A new fragment with Roboto should be inserted, original stays intact
      expect(p.fragments.length, greaterThan(1));
      final newFrag = p.fragments.firstWhere((f) => (f as Fragment).text == 'X') as Fragment;
      expect(newFrag.fontFamily, 'Roboto');
    });

    test('creates paragraph in empty document', () {
      document = FluentDocument(content: Root(nodes: []));
      document.eventHandler.document = document;
      document.cursor.moveTo(document.content.id, 0);
      executeHandleInsertCharacter('h', document);
      expect(document.content.nodes.length, 1);
      expect(document.content.nodes.first is Paragraph, isTrue);
    });

    test('inserts before image at offset 0', () {
      final img = FluentImage('https://img.png');
      final p = Paragraph()..fragments = [img];
      document = FluentDocument(content: Root(nodes: [p]));
      document.eventHandler.document = document;
      document.cursor.moveTo(img.id, 0);
      executeHandleInsertCharacter('x', document);
      expect(p.fragments.length, 2);
      expect((p.fragments.first as Fragment).text, 'x');
    });

    test('inserts after image at offset 1', () {
      final img = FluentImage('https://img.png');
      final p = Paragraph()..fragments = [img];
      document = FluentDocument(content: Root(nodes: [p]));
      document.eventHandler.document = document;
      document.cursor.moveTo(img.id, 1);
      executeHandleInsertCharacter('x', document);
      expect(p.fragments.length, 2);
      expect((p.fragments.last as Fragment).text, 'x');
    });

    test('inserts before HorizontalRule', () {
      final hr = HorizontalRule();
      final root = Root(nodes: [hr]);
      document = FluentDocument(content: root);
      document.eventHandler.document = document;
      document.cursor.moveTo(hr.id, 0);
      executeHandleInsertCharacter('x', document);
      expect(root.nodes.length, 2);
      expect(root.nodes.first is Paragraph, isTrue);
      expect((root.nodes.first as Paragraph).text, 'x');
    });
  });
}
