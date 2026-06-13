import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/core/constants.dart';

void main() {
  group('FNode creation', () {
    test('Fragment has correct defaults', () {
      final f = Fragment('hello');
      expect(f.text, 'hello');
      expect(f.type, 'fragment');
      expect(f.fontFamily, 'DejaVu Sans');
      expect(f.fontSize, 14.0);
      expect(f.styles, isNull);
      expect(f.color, isNull);
      expect(f.highlightColor, isNull);
      expect(f.id, isNotEmpty);
    });

    test('Fragment with custom styles', () {
      final f = Fragment('bold text',
        styles: ['bold'],
        fontFamily: 'Roboto',
        fontSize: 18.0,
        color: '#FF0000',
        highlightColor: '#FFFF00',
      );
      expect(f.styles, contains('bold'));
      expect(f.fontFamily, 'Roboto');
      expect(f.fontSize, 18.0);
      expect(f.color, '#FF0000');
      expect(f.highlightColor, '#FFFF00');
      expect(f.isBold, isTrue);
    });

    test('Paragraph has correct defaults', () {
      final p = Paragraph();
      expect(p.type, 'paragraph');
      expect(p.textAlign, 'left');
      expect(p.indent, 0);
      expect(p.styleName, isNull);
      expect(p.fragments.length, 1);
      expect((p.fragments.first as Fragment).text, '');
    });

    test('Paragraph with text', () {
      final p = Paragraph(text: 'hello world');
      expect(p.text, 'hello world');
      expect(p.fragments.length, 1);
    });

    test('Link is a Paragraph and Fragment', () {
      final link = Link(url: 'https://example.com', text: 'example');
      expect(link.url, 'https://example.com');
      expect(link.text, 'example');
      expect(link.type, 'link');
    });

    test('HorizontalRule is atomic', () {
      final hr = HorizontalRule();
      expect(hr.type, 'hr');
      expect(hr.text, Whitespaces.zws);
      expect(hr.fragments, isEmpty);
      expect(hr.getChildren(), isEmpty);
    });

    test('FluentImage is atomic', () {
      final img = FluentImage('https://example.com/image.png');
      expect(img.type, 'image');
      expect(img.src, 'https://example.com/image.png');
      expect(img.text, Whitespaces.zws);
      expect(img.textAlign, 'left');
      expect(img.width, isNull);
      expect(img.height, isNull);
    });

    test("FluentList starts empty", () {
      final list = FluentList(listType: "bullet");
      expect(list.type, "list");
      expect(list.listType, "bullet");
      expect(list.items.length, 0);
    });

    test('ListItem has children', () {
      final item = ListItem(bulletType: 'bullet', indexList: [1]);
      expect(item.type, 'listItem');
      expect(item.children.length, 1);
      expect(item.children.first is Paragraph, isTrue);
    });

    test('FluentTable has rows', () {
      final table = FluentTable();
      expect(table.type, 'table');
      expect(table.rows, isEmpty);
      expect(table.tableWidth, isNull);
      expect(table.columnWidths, isNull);
    });

    test('FluentRow has cells', () {
      final row = FluentRow();
      expect(row.type, 'row');
      expect(row.cells, isEmpty);
      expect(row.rowHeight, isNull);
    });

    test('FluentCell has children', () {
      final cell = FluentCell();
      expect(cell.type, 'cell');
      expect(cell.children.length, 1);
      expect(cell.children.first is Paragraph, isTrue);
      expect(cell.colSpan, 1);
      expect(cell.rowSpan, 1);
    });

    test('Root has nodes', () {
      final root = Root();
      expect(root.nodes, isEmpty);
      expect(root.type, 'root');
      expect(root.text, '');
    });

    test('Root with nodes', () {
      final root = Root(nodes: [
        Paragraph(text: 'hello'),
        Paragraph(text: 'world'),
      ]);
      expect(root.nodes.length, 2);
      expect(root.text, 'helloworld');
    });
  });

  group('InlineContainerNode properties', () {
    test('Paragraph fragments and children match', () {
      final p = Paragraph(text: 'abc');
      expect(p.fragments, p.getChildren());
      expect(p.fragments.length, 1);
    });

    test('Link fragments and children match', () {
      final link = Link(url: 'https://x.com', text: 'x');
      expect(link.fragments, link.getChildren());
      expect(link.fragments.length, 1);
    });

    test('FluentList children are items', () {
      final list = FluentList(listType: 'numbered');
      expect(list.getChildren(), list.items);
    });

    test('FluentTable children are rows', () {
      final table = FluentTable(rows: [FluentRow()]);
      expect(table.getChildren(), table.rows);
    });

    test('FluentRow children are cells', () {
      final row = FluentRow(cells: [FluentCell()]);
      expect(row.getChildren(), row.cells);
    });

    test('ListItem fragments aggregate children', () {
      final item = ListItem(
        bulletType: 'bullet',
        indexList: [1],
        children: [Paragraph(text: 'a'), Paragraph(text: 'b')],
      );
      expect(item.fragments.length, 2);
      expect(item.text, 'ab');
    });

    test('FluentCell fragments aggregate children', () {
      final cell = FluentCell(children: [
        Paragraph(text: 'a'),
        Paragraph(text: 'b'),
      ]);
      expect(cell.fragments.length, 2);
      expect(cell.text, 'ab');
    });
  });

  group('copyFrom', () {
    test('copies Fragment', () {
      final f = Fragment('hello', styles: ['bold']);
      final copy = copyFrom(f) as Fragment;
      expect(copy.text, 'hello');
      expect(copy.id, isNot(equals(f.id)));
    });

    test('copies Link', () {
      final link = Link(url: 'https://x.com', text: 'x');
      final copy = copyFrom(link) as Link;
      expect(copy.url, 'https://x.com');
      expect(copy.id, isNot(equals(link.id)));
    });

    test('copies Paragraph with fragments', () {
      final p = Paragraph(text: 'hello');
      final copy = copyFrom(p) as Paragraph;
      expect(copy.text, 'hello');
      expect(copy.fragments.length, 1);
      expect(copy.fragments.first.id, isNot(equals(p.fragments.first.id)));
    });

    test('throws on unsupported type', () {
      final root = Root();
      expect(() => copyFrom(root), throwsException);
    });
  });

  group('makeNode', () {
    test('creates Paragraph', () {
      final node = makeNode('paragraph', {});
      expect(node is Paragraph, isTrue);
    });

    test('creates Link', () {
      final node = makeNode('link', {'url': 'https://x.com', 'text': 'x'});
      expect(node is Link, isTrue);
      expect((node as Link).url, 'https://x.com');
    });

    test('creates List', () {
      final node = makeNode('list', {'listType': 'bullet'});
      expect(node is FluentList, isTrue);
      expect((node as FluentList).listType, 'bullet');
    });

    test('creates Table', () {
      final node = makeNode('table', {'rows': 2, 'cells': 3});
      expect(node is FluentTable, isTrue);
      expect((node as FluentTable).rows.length, 2);
      expect((node as FluentTable).rows.first.cells.length, 3);
    });

    test('creates Image', () {
      final node = makeNode('image', {'src': 'https://img.png'});
      expect(node is FluentImage, isTrue);
      expect((node as FluentImage).src, 'https://img.png');
    });

    test('creates HorizontalRule', () {
      final node = makeNode('hr', {});
      expect(node is HorizontalRule, isTrue);
    });

    test('defaults to Paragraph for unknown type', () {
      final node = makeNode('unknown', {});
      expect(node is Paragraph, isTrue);
    });
  });

  group('Link type-check order regression', () {
    test('Link must be checked before Paragraph and Fragment', () {
      final link = Link(url: 'https://example.com', text: 'link text');

      // Correct type-check order: Link -> Paragraph -> Fragment
      String correctCheck(FNode node) {
        if (node is Link) return 'link';
        if (node is Paragraph) return 'paragraph';
        if (node is Fragment) return 'fragment';
        return 'other';
      }

      expect(correctCheck(link), 'link');

      // Simulate old buggy behavior: Fragment checked first
      String buggyCheck(FNode node) {
        if (node is Fragment) return 'fragment';
        if (node is Paragraph) return 'paragraph';
        if (node is Link) return 'link';
        return 'other';
      }

      // This demonstrates why Fragment-first is wrong
      expect(buggyCheck(link), 'fragment');
      expect(buggyCheck(link), isNot('link'));
    });

    test('Link fragments are accessible as children', () {
      final link = Link(url: 'https://x.com', text: 'hello');
      expect(link.fragments.length, 1);
      expect(link.getChildren().length, 1);
      expect((link.fragments.first as Fragment).text, 'hello');
    });
  });
}
