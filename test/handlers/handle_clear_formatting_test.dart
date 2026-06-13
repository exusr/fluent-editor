import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_clear_formatting.dart';

void main() {
  group('executeHandleClearFormatting', () {
    test('removes all styles from selected text', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      f.styles = ['bold', 'italic'];
      f.fontFamily = 'Roboto';
      f.fontSize = 24.0;
      f.color = '#FF0000';
      f.highlightColor = '#FFFF00';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleClearFormatting(doc);
      expect(f.styles ?? [], isEmpty);
      expect(f.color, isNull);
      expect(f.highlightColor, isNull);
    });
  });
}
