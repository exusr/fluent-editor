import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_formats.dart';

void main() {
  group('executeHandleBold', () {
    test('applies bold to selected text', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleBold(doc);
      expect(f.styles, contains('bold'));
    });

    test('removes bold when already bold', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      f.styles = ['bold'];
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleBold(doc);
      expect(f.styles ?? [], isNot(contains('bold')));
    });
  });

  group('executeHandleItalic', () {
    test('applies italic to selected text', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleItalic(doc);
      expect(f.styles, contains('italic'));
    });
  });

  group('executeHandleUnderline', () {
    test('applies underline to selected text', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleUnderline(doc);
      expect(f.styles, contains('underline'));
    });
  });
}
