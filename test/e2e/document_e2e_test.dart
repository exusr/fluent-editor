import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';

void main() {
  group('Document e2e — JSON round-trip', () {
    test('simple paragraph round-trips through JSON', () {
      final p = Paragraph(text: 'hello world');
      final doc = FluentDocument(content: Root(nodes: [p]));

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(decoded.content.nodes.length, 1);
      expect(decoded.content.text, 'hello world');
    });

    test('multiple paragraphs round-trip through JSON', () {
      final doc = FluentDocument(content: Root(nodes: [
        Paragraph(text: 'first'),
        Paragraph(text: 'second'),
        Paragraph(text: 'third'),
      ]));

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(decoded.content.nodes.length, 3);
      expect((decoded.content.nodes[0] as Paragraph).text, 'first');
      expect((decoded.content.nodes[1] as Paragraph).text, 'second');
      expect((decoded.content.nodes[2] as Paragraph).text, 'third');
    });

    test('list round-trips through JSON', () {
      final list = FluentList(listType: 'bullet');
      list.items = [
        ListItem(
          bulletType: 'bullet',
          indexList: [1],
          children: [Paragraph(text: 'item 1')],
        ),
        ListItem(
          bulletType: 'bullet',
          indexList: [2],
          children: [Paragraph(text: 'item 2')],
        ),
      ];
      final doc = FluentDocument(content: Root(nodes: [list]));

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(decoded.content.nodes.length, 1);
      final decodedList = decoded.content.nodes.first as FluentList;
      expect(decodedList.items.length, 2);
      expect(decodedList.items[0].text, contains('item 1'));
      expect(decodedList.items[1].text, contains('item 2'));
    });

    test('link round-trips through JSON', () {
      final link = Link(url: 'https://example.com');
      link.fragments = [Fragment('click here')];
      final p = Paragraph(text: '');
      p.fragments = [Fragment('before'), link, Fragment('after')];
      final doc = FluentDocument(content: Root(nodes: [p]));

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      final decodedP = decoded.content.nodes.first as Paragraph;
      // Link should be preserved
      final links = decodedP.fragments.whereType<Link>().toList();
      expect(links.length, 1);
      expect(links.first.url, 'https://example.com');
      expect(links.first.text, 'click here');
    });

    test('horizontal rule round-trips through JSON', () {
      final doc = FluentDocument(content: Root(nodes: [
        Paragraph(text: 'before'),
        HorizontalRule(),
        Paragraph(text: 'after'),
      ]));

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(decoded.content.nodes.length, 3);
      expect(decoded.content.nodes[1], isA<HorizontalRule>());
    });

    test('image round-trips through JSON', () {
      final image = FluentImage('https://example.com/img.png');
      final p = Paragraph(text: '');
      p.fragments = [image];
      final doc = FluentDocument(content: Root(nodes: [p]));

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      final decodedP = decoded.content.nodes.first as Paragraph;
      final images = decodedP.fragments.whereType<FluentImage>().toList();
      expect(images.length, 1);
    });
  });

  group('Document e2e — settings persistence', () {
    test('settings round-trip through JSON', () {
      final doc = FluentDocument();
      doc.pendingFontFamily = 'Lato';
      doc.pendingFontSize = 18.0;
      doc.pendingLineHeight = 1.5;
      doc.pendingTextAlign = 'center';
      doc.pendingIndent = 2;

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(decoded.pendingFontFamily, 'Lato');
      expect(decoded.pendingFontSize, 18.0);
      expect(decoded.pendingLineHeight, 1.5);
      expect(decoded.pendingTextAlign, 'center');
      expect(decoded.pendingIndent, 2);
    });
  });

  group('Document e2e — cursor survives load', () {
    test('cursor points to first fragment after load', () {
      final doc = FluentDocument(content: Root(nodes: [
        Paragraph(text: 'hello'),
        Paragraph(text: 'world'),
      ]));

      final json = doc.toJson();
      final decoded = FluentDocument.fromJson(jsonDecode(json) as Map<String, dynamic>);

      // Cursor should be on the first paragraph's first fragment
      final firstP = decoded.content.nodes.first as Paragraph;
      final firstFrag = firstP.fragments.first as Fragment;
      expect(decoded.cursor.anchorId, firstFrag.id);
      expect(decoded.cursor.anchorOffset, 0);
    });
  });

  group('Document e2e — nodeById', () {
    test('nodeById finds existing nodes', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: 'world');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));

      expect(doc.nodeById(p1.id), isNotNull);
      expect(doc.nodeById(p2.id), isNotNull);
      expect(doc.nodeById('nonexistent'), isNull);
    });

    test('nodeById finds nested fragments', () {
      final p = Paragraph(text: 'hello');
      final frag = p.fragments.first as Fragment;
      final doc = FluentDocument(content: Root(nodes: [p]));

      expect(doc.nodeById(frag.id), isNotNull);
      expect(doc.nodeById(frag.id), isA<Fragment>());
    });
  });

  group('Document e2e — content text', () {
    test('content.text aggregates all paragraph text', () {
      final doc = FluentDocument(content: Root(nodes: [
        Paragraph(text: 'hello'),
        Paragraph(text: ' '),
        Paragraph(text: 'world'),
      ]));

      expect(doc.content.text, 'hello world');
    });

    test('content.text includes list items', () {
      final list = FluentList(listType: 'bullet');
      list.items = [
        ListItem(
          bulletType: 'bullet',
          indexList: [1],
          children: [Paragraph(text: 'one')],
        ),
        ListItem(
          bulletType: 'bullet',
          indexList: [2],
          children: [Paragraph(text: 'two')],
        ),
      ];
      final doc = FluentDocument(content: Root(nodes: [list]));

      expect(doc.content.text, contains('one'));
      expect(doc.content.text, contains('two'));
    });
  });
}
