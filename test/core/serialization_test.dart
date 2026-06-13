import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';

void main() {
  group('Fragment serialization', () {
    test('round-trip with defaults', () {
      final f = Fragment('hello');
      final json = f.toJson();
      final restored = Fragment.fromJson(json);
      expect(restored.text, f.text);
      expect(restored.fontFamily, f.fontFamily);
      expect(restored.fontSize, f.fontSize);
      expect(restored.styles, isNull);
      expect(restored.color, isNull);
      expect(restored.highlightColor, isNull);
    });

    test('round-trip with custom styles', () {
      final f = Fragment('hello',
        styles: ['bold', 'italic'],
        fontFamily: 'Roboto',
        fontSize: 18.0,
        color: '#FF0000',
        highlightColor: '#FFFF00',
      );
      final json = f.toJson();
      final restored = Fragment.fromJson(json);
      expect(restored.text, 'hello');
      expect(restored.styles, containsAll(['bold', 'italic']));
      expect(restored.fontFamily, 'Roboto');
      expect(restored.fontSize, 18.0);
      expect(restored.color, '#FF0000');
      expect(restored.highlightColor, '#FFFF00');
    });

    test('does not serialize default fontSize', () {
      final f = Fragment('hello', fontSize: 14.0);
      final json = f.toJson();
      expect(json.containsKey('fontSize'), isTrue);
    });

    test('does not serialize default styles', () {
      final f = Fragment('hello');
      final json = f.toJson();
      expect(json.containsKey('styles'), isTrue);
    });
  });

  group('Paragraph serialization', () {
    test('round-trip with defaults', () {
      final p = Paragraph(text: 'hello');
      final json = p.toJson();
      final restored = Paragraph.fromJson(json);
      expect(restored.text, 'hello');
      expect(restored.textAlign, 'left');
      expect(restored.indent, 0);
      expect(restored.styleName, isNull);
    });

    test('round-trip with custom alignment and indent', () {
      final p = Paragraph(text: 'hello', textAlign: 'center', indent: 2);
      final json = p.toJson();
      final restored = Paragraph.fromJson(json);
      expect(restored.textAlign, 'center');
      expect(restored.indent, 2);
    });

    test('round-trip with fragments', () {
      final p = Paragraph();
      p.fragments = [
        Fragment('hello', styles: ['bold']),
        Fragment(' world', color: '#FF0000'),
      ];
      final json = p.toJson();
      final restored = Paragraph.fromJson(json);
      expect(restored.fragments.length, 2);
      expect((restored.fragments[0] as Fragment).text, 'hello');
      expect((restored.fragments[0] as Fragment).styles, contains('bold'));
      expect((restored.fragments[1] as Fragment).color, '#FF0000');
    });
  });

  group('Link serialization', () {
    test('round-trip preserves url and text', () {
      final link = Link(url: 'https://example.com', text: 'example');
      final json = link.toJson();
      final restored = Link.fromJson(json);
      expect(restored.url, 'https://example.com');
      expect(restored.text, 'example');
      expect(restored.type, 'link');
    });
  });

  group('FluentImage serialization', () {
    test('round-trip with defaults', () {
      final img = FluentImage('https://img.png');
      final json = img.toJson();
      final restored = FluentImage.fromJson(json);
      expect(restored.src, 'https://img.png');
      expect(restored.textAlign, 'left');
      expect(restored.width, isNull);
      expect(restored.height, isNull);
    });

    test('round-trip with dimensions', () {
      final img = FluentImage('https://img.png')
        ..textAlign = 'center'
        ..width = 200.0
        ..height = 100.0;
      final json = img.toJson();
      final restored = FluentImage.fromJson(json);
      expect(restored.textAlign, 'center');
      expect(restored.width, 200.0);
      expect(restored.height, 100.0);
    });
  });

  group('HorizontalRule serialization', () {
    test('round-trip preserves id', () {
      final hr = HorizontalRule();
      final json = hr.toJson();
      final restored = HorizontalRule.fromJson(json);
      expect(restored.type, 'hr');
      expect(restored.id, hr.id);
    });
  });

  group('FluentList serialization', () {
    test('round-trip preserves listType and items', () {
      final list = FluentList(listType: 'numbered');
      list.items.add(ListItem(bulletType: 'numbered', indexList: [1, 2]));
      final json = jsonDecode(jsonEncode(list.toJson())) as Map<String, dynamic>;
      final restored = FluentList.fromJson(json);
      expect(restored.listType, 'numbered');
      expect(restored.items.length, 1);
    });
  });

  group('FluentTable serialization', () {
    test('round-trip with rows and cells', () {
      final table = FluentTable(
        rows: [
          FluentRow(cells: [
            FluentCell(children: [Paragraph(text: 'a')]),
            FluentCell(children: [Paragraph(text: 'b')]),
          ]),
        ],
        tableWidth: 400.0,
        columnWidths: [100.0, 300.0],
      );
      final json = jsonDecode(jsonEncode(table.toJson())) as Map<String, dynamic>;
      final restored = FluentTable.fromJson(json);
      expect(restored.rows.length, 1);
      expect(restored.rows.first.cells.length, 2);
      expect(restored.tableWidth, 400.0);
      expect(restored.columnWidths, [100.0, 300.0]);
    });
  });

  group('FluentRow serialization', () {
    test('round-trip with rowHeight', () {
      final row = FluentRow(
        cells: [FluentCell(), FluentCell()],
        rowHeight: 50.0,
      );
      final json = jsonDecode(jsonEncode(row.toJson())) as Map<String, dynamic>;
      final restored = FluentRow.fromJson(json);
      expect(restored.cells.length, 2);
      expect(restored.rowHeight, 50.0);
    });
  });

  group('FluentCell serialization', () {
    test('round-trip with colspan and rowspan', () {
      final cell = FluentCell(children: [Paragraph(text: 'hello')])
        ..colSpan = 2
        ..rowSpan = 3;
      final json = cell.toJson();
      final restored = FluentCell.fromJson(json);
      expect(restored.colSpan, 2);
      expect(restored.rowSpan, 3);
      expect(restored.children.length, 1);
    });
  });

  group('Root serialization', () {
    test('round-trip with multiple nodes', () {
      final root = Root(nodes: [
        Paragraph(text: 'hello'),
        FluentList(listType: 'bullet'),
      ]);
      final json = jsonDecode(jsonEncode(root.toJson())) as Map<String, dynamic>;
      final restored = Root.fromJson(json);
      expect(restored.nodes.length, 2);
      expect(restored.nodes[0] is Paragraph, isTrue);
      expect(restored.nodes[1] is FluentList, isTrue);
    });
  });

  group('FNodeJsonConverter', () {
    const converter = FNodeJsonConverter();

    test('converts Fragment', () {
      final json = {'type': 'fragment', 'id': 'f1', 'text': 'hello', 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0};
      final node = converter.fromJson(json);
      expect(node is Fragment, isTrue);
    });

    test('converts Paragraph', () {
      final json = {'type': 'paragraph', 'id': 'p1', 'fragments': []};
      final node = converter.fromJson(json);
      expect(node is Paragraph, isTrue);
    });

    test('converts Link', () {
      final json = {'type': 'link', 'id': 'l1', 'url': 'https://x.com', 'fragments': [], 'textAlign': 'left', 'indent': 0, 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0, 'styles': []};
      final node = converter.fromJson(json);
      expect(node is Link, isTrue);
    });

    test('converts FluentImage', () {
      final json = {'type': 'image', 'id': 'i1', 'src': 'https://img.png', 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0, 'text': '', 'textAlign': 'left'};
      final node = converter.fromJson(json);
      expect(node is FluentImage, isTrue);
    });

    test('converts HorizontalRule', () {
      final json = {'type': 'hr', 'id': 'hr1'};
      final node = converter.fromJson(json);
      expect(node is HorizontalRule, isTrue);
    });

    test('converts FluentList', () {
      final json = {'type': 'list', 'id': 'list1', 'listType': 'bullet', 'fragments': [], 'textAlign': 'left', 'indent': 0, 'items': []};
      final node = converter.fromJson(json);
      expect(node is FluentList, isTrue);
    });

    test('converts ListItem', () {
      final json = {'type': 'listItem', 'id': 'li1', 'bulletType': 'bullet', 'indexList': [1], 'fragments': [], 'children': [], 'text': '', 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0};
      final node = converter.fromJson(json);
      expect(node is ListItem, isTrue);
    });

    test('converts FluentTable', () {
      final json = {'type': 'table', 'id': 't1', 'rows': []};
      final node = converter.fromJson(json);
      expect(node is FluentTable, isTrue);
    });

    test('converts FluentRow', () {
      final json = {'type': 'row', 'id': 'r1', 'cells': []};
      final node = converter.fromJson(json);
      expect(node is FluentRow, isTrue);
    });

    test('converts FluentCell', () {
      final json = {'type': 'cell', 'id': 'c1', 'children': []};
      final node = converter.fromJson(json);
      expect(node is FluentCell, isTrue);
    });

    test('throws on unknown type', () {
      final json = {'type': 'unknown', 'id': 'u1'};
      expect(() => converter.fromJson(json), throwsException);
    });
  });

  group('FluentDocument JSON formats', () {
    test('legacy format (Root directly)', () {
      final json = {
        'type': 'root',
        'id': 'root1',
        'nodes': [
          {'type': 'paragraph', 'id': 'p1', 'fragments': [{'type': 'fragment', 'id': 'f1', 'text': 'hello', 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0}]}
        ]
      };
      final doc = FluentDocument.fromJson(json);
      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'hello');
    });

    test('new format with settings', () {
      final json = {
        'nodes': {
          'type': 'root',
          'id': 'root1',
          'nodes': [
            {'type': 'paragraph', 'id': 'p1', 'fragments': [{'type': 'fragment', 'id': 'f1', 'text': 'hello', 'fontFamily': 'DejaVu Sans', 'fontSize': 14.0}]}
          ]
        },
        'settings': {
          'lineHeight': 2.0,
          'spacingBefore': 24.0,
          'spacingAfter': 12.0,
          'fontFamily': 'Roboto',
          'fontSize': 16.0,
          'textAlign': 'center',
        }
      };
      final doc = FluentDocument.fromJson(json);
      expect(doc.content.nodes.length, 1);
      expect(doc.pendingLineHeight, 2.0);
      expect(doc.pendingSpacingBefore, 24.0);
      expect(doc.pendingSpacingAfter, 12.0);
      expect(doc.pendingFontFamily, 'Roboto');
      expect(doc.pendingFontSize, 16.0);
      expect(doc.pendingTextAlign, 'center');
    });

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
  });

  group('Complex nested document', () {
    test('list inside table round-trip', () {
      final root = Root(nodes: [
        FluentTable(rows: [
          FluentRow(cells: [
            FluentCell(children: [
              FluentList(listType: 'bullet')
                ..items.add(ListItem(bulletType: 'bullet', indexList: [1])),
            ]),
          ]),
        ]),
      ]);
      final json = jsonDecode(jsonEncode(root.toJson())) as Map<String, dynamic>;
      final restored = Root.fromJson(json);
      final table = restored.nodes.first as FluentTable;
      final cell = table.rows.first.cells.first;
      final list = cell.children.first as FluentList;
      expect(list.items.first.bulletType, 'bullet');
    });

    test('link inside paragraph round-trip', () {
      final p = Paragraph();
      p.fragments = [
        Fragment('visit '),
        Link(url: 'https://x.com', text: 'x.com'),
        Fragment(' please'),
      ];
      final json = p.toJson();
      final restored = Paragraph.fromJson(json);
      expect(restored.fragments.length, 3);
      expect(restored.fragments[1] is Link, isTrue);
      expect((restored.fragments[1] as Link).url, 'https://x.com');
    });
  });
}
