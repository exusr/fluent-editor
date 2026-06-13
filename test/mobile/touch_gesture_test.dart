import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';

void main() {
  group('Mobile touch/gesture basics', () {
    test('document creates with default structure for mobile', () {
      final doc = FluentDocument();
      expect(doc.content.nodes.length, 1);
      expect(doc.content.nodes.first is Paragraph, isTrue);
    });

    test('cursor can be positioned for tap simulation', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello world';
      doc.cursor.moveTo(f.id, 5);
      expect(doc.cursor.anchorOffset, 5);
      expect(doc.cursor.isCollapsed, isTrue);
    });

    test('selection can be created for gesture simulation', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello world';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      expect(doc.cursor.isCollapsed, isFalse);
      expect(doc.cursor.focusOffset, 5);
    });
  });
}
