import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_tab.dart';

void main() {
  group('executeHandleTab', () {
    test('TAB increases paragraph indent', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      p.indent = 0;
      doc.cursor.moveTo((p.fragments.first as Fragment).id, 0);
      final result = executeHandleTab(doc);
      expect(result, isTrue);
      expect(p.indent, 1);
    });

    test('TAB at max indent does nothing', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      p.indent = 10;
      doc.cursor.moveTo((p.fragments.first as Fragment).id, 0);
      final result = executeHandleTab(doc);
      expect(result, isTrue);
      expect(p.indent, 10);
    });

    test('SHIFT+TAB decreases paragraph indent', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      p.indent = 2;
      doc.cursor.moveTo((p.fragments.first as Fragment).id, 0);
      final result = executeHandleTab(doc, shift: true);
      expect(result, isTrue);
      expect(p.indent, 1);
    });

    test('SHIFT+TAB at zero indent leaves paragraph unchanged', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      p.indent = 0;
      doc.cursor.moveTo((p.fragments.first as Fragment).id, 0);
      final result = executeHandleTab(doc, shift: true);
      expect(result, isTrue);
      expect(p.indent, 0);
    });
  });

  group('executeHandleOutdent', () {
    test('outdent on non-list item does not modify document', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final originalIndent = p.indent;
      doc.cursor.moveTo((p.fragments.first as Fragment).id, 0);
      executeHandleOutdent(doc);
      expect(p.indent, originalIndent);
    });
  });
}
