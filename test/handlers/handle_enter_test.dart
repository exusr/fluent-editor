import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/handlers/handle_enter.dart';

void main() {
  late FluentDocument document;

  setUp(() {
    document = FluentDocument();
    document.eventHandler.document = document;
  });

  group('executeHandleEnter', () {
    test('splits paragraph in middle', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'hello world';
      document.cursor.moveTo(frag.id, 5);
      executeHandleEnter(document);
      expect(document.content.nodes.length, 2);
      expect(document.content.text, 'hello world');
      expect((document.content.nodes[0] as Paragraph).text, 'hello');
      expect((document.content.nodes[1] as Paragraph).text, ' world');
    });

    test('creates empty paragraph at end', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'hello';
      document.cursor.moveTo(frag.id, 5);
      executeHandleEnter(document);
      expect(document.content.nodes.length, 2);
      expect((document.content.nodes[0] as Paragraph).text, 'hello');
      expect((document.content.nodes[1] as Paragraph).text, '');
    });

    test('creates empty paragraph at beginning', () {
      final p = document.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      frag.text = 'hello';
      document.cursor.moveTo(frag.id, 0);
      executeHandleEnter(document);
      expect(document.content.nodes.length, 2);
      expect((document.content.nodes[0] as Paragraph).text, '');
      expect((document.content.nodes[1] as Paragraph).text, 'hello');
    });

    test('in list creates new list item', () {
      final item = ListItem(
        bulletType: 'bullet',
        indexList: [1],
        children: [Paragraph(text: 'hello')],
      );
      final list = FluentList(listType: 'bullet')..items.add(item);
      document = FluentDocument(content: Root(nodes: [list]));
      document.eventHandler.document = document;
      final frag = (item.children.first as Paragraph).fragments.first as Fragment;
      document.cursor.moveTo(frag.id, 5);
      executeHandleEnter(document);
      expect(list.items.length, 2);
      expect(list.items[0].children.first is Paragraph, isTrue);
    });

    test('returns false when cursor not found', () {
      document.cursor.moveTo('unknown-id', 0);
      final result = executeHandleEnter(document);
      expect(result, isFalse);
    });
  });
}
