import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';

void main() {
  group('Document integration', () {
    test('complex document round-trip via JSON', () {
      final doc = FluentDocument();
      final root = Root(nodes: [
        Paragraph(text: 'Title', textAlign: 'center'),
        FluentList(listType: 'bullet')
          ..items.add(ListItem(bulletType: 'bullet', indexList: [1]))
          ..items.add(ListItem(bulletType: 'bullet', indexList: [2])),
        FluentTable(rows: [
          FluentRow(cells: [
            FluentCell(children: [Paragraph(text: 'Cell 1')]),
            FluentCell(children: [Paragraph(text: 'Cell 2')]),
          ]),
        ]),
      ]);
      doc.load(root.nodes);

      final jsonStr = doc.toJson();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = FluentDocument.fromJson(decoded);

      expect(restored.content.nodes.length, 3);
      expect(restored.content.nodes[0] is Paragraph, isTrue);
      expect(restored.content.nodes[1] is FluentList, isTrue);
      expect(restored.content.nodes[2] is FluentTable, isTrue);
    });

    test('settings persist across round-trip', () {
      final doc = FluentDocument();
      doc.pendingFontFamily = 'Roboto';
      doc.pendingFontSize = 18.0;
      doc.pendingTextAlign = 'center';

      final jsonStr = doc.toJson();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restored = FluentDocument.fromJson(decoded);

      expect(restored.pendingFontFamily, 'Roboto');
      expect(restored.pendingFontSize, 18.0);
      expect(restored.pendingTextAlign, 'center');
    });

    test('cursor survives load', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 3);
      expect(doc.cursor.anchorOffset, 3);
      expect(doc.cursor.isCollapsed, isTrue);
    });
  });
}
