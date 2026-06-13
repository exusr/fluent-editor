import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_select_all.dart';

void main() {
  group('handleSelectAll', () {
    test('selects all content in document', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello world';
      doc.cursor.moveTo(f.id, 0);
      handleSelectAll(doc);
      expect(doc.cursor.isCollapsed, isFalse);
      expect(doc.cursor.anchorId, f.id);
      expect(doc.cursor.anchorOffset, 0);
      expect(doc.cursor.focusOffset, f.text.length);
    });
  });
}
