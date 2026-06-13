import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_font_family.dart';
import 'package:fluent_editor/handlers/handle_font_size.dart';

void main() {
  group('executeHandleFontFamily', () {
    test('changes font family of selected text', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleFontFamily(doc, 'Roboto');
      expect(f.fontFamily, 'Roboto');
    });
  });

  group('executeHandleFontSize', () {
    test('changes font size of selected text', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleFontSize(doc, 24.0);
      expect(f.fontSize, 24.0);
    });
  });
}
