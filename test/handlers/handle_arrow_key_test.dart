import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_arrow_key.dart';

void main() {
  group('executeHandleArrowKey', () {
    test('move right in same fragment', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 2);
      executeHandleArrowKey(LogicalKeyboardKey.arrowRight, doc);
      expect(doc.cursor.anchorOffset, 3);
    });

    test('move left in same fragment', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 3);
      executeHandleArrowKey(LogicalKeyboardKey.arrowLeft, doc);
      expect(doc.cursor.anchorOffset, 2);
    });

    test('move down to next line', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello world';
      doc.cursor.moveTo(f.id, 0);
      executeHandleArrowKey(LogicalKeyboardKey.arrowDown, doc);
      expect(doc.cursor.anchorOffset, greaterThanOrEqualTo(0));
    });

    test('move up to previous line', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello world';
      doc.cursor.moveTo(f.id, f.text.length);
      executeHandleArrowKey(LogicalKeyboardKey.arrowUp, doc);
      expect(doc.cursor.anchorOffset, greaterThanOrEqualTo(0));
    });

    test('move right at end of fragment moves to next fragment', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f1 = Fragment('hello');
      final f2 = Fragment(' world');
      p.fragments = [f1, f2];
      doc.cursor.moveTo(f1.id, 5);
      executeHandleArrowKey(LogicalKeyboardKey.arrowRight, doc);
      expect(doc.cursor.anchorId, f2.id);
      expect(doc.cursor.anchorOffset, 0);
    });

    test('move left within fragment', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 1);
      executeHandleArrowKey(LogicalKeyboardKey.arrowLeft, doc);
      expect(doc.cursor.anchorId, f.id);
      expect(doc.cursor.anchorOffset, 0);
    });
  });
}
