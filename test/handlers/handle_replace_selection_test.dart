import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';

void main() {
  group('executeHandleReplaceSelection', () {
    test('replaces selected text with replacement', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello world';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleReplaceSelection('hi', doc);
      expect(doc.content.text, 'hi world');
    });

    test('replaces entire text with replacement', () {
      final doc = FluentDocument();
      final p = doc.content.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      f.text = 'hello';
      doc.cursor.moveTo(f.id, 0);
      doc.cursor.focusTo(f.id, 5);
      executeHandleReplaceSelection('replaced', doc);
      expect(doc.content.text, 'replaced');
    });
  });
}
