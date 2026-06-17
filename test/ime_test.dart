import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/input/ime_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('FluentTextInputHandler', () {
    late FluentDocument doc;
    late FluentTextInputHandler handler;

    setUp(() {
      doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'Hello world')]));
      doc.cursor.document = doc;
      doc.eventHandler.document = doc;
      handler = doc.imeHandler;
      handler.attachInput(doc);
    });

    tearDown(() {
      handler.detachInput();
    });

    test('currentTextEditingValue returns full buffer during composition on iOS', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      // Simulate iOS buffer-sync platform.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Start composition: the full buffer the IME sees is "Hello aworld"
      // with composing range (6, 7) around the preedit 'a'.
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'Hello aworld',
          composing: TextRange(start: 6, end: 7),
        ),
      );

      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, 'a');

      // currentTextEditingValue must return the full buffer so that
      // subsequent deltas from the IME are applied to a consistent base.
      final value = handler.currentTextEditingValue!;
      expect(value.text, 'Hello aworld');
      expect(value.composing, const TextRange(start: 6, end: 7));
      expect(value.selection, const TextSelection.collapsed(offset: 7));
    });

    test('IME preedit single character', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'a',
          composing: TextRange(start: 0, end: 1),
        ),
      );

      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, 'a');
      expect(doc.cursor.imeComposing, isTrue);
      expect(doc.cursor.imeComposingStart, 5);
    });

    test('IME preedit multi-character CJK', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      handler.updateEditingValue(
        const TextEditingValue(
          text: '\u3053\u3093\u306b\u3061\u306f',
          composing: TextRange(start: 0, end: 5),
        ),
      );

      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, '\u3053\u3093\u306b\u3061\u306f');
      expect(handler.preeditText.length, 5);
    });

    test('IME commit finalizes text', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);
      final beforeUndoCount = doc.undoRedoManager.undoCount;

      handler.updateEditingValue(
        const TextEditingValue(
          text: '\u3053\u3093\u306b\u3061\u306f',
          composing: TextRange(start: 0, end: 5),
        ),
      );
      expect(handler.isComposing, isTrue);

      // Commit by sending an invalid composing range.
      handler.updateEditingValue(
        const TextEditingValue(
          text: '\u3053\u3093\u306b\u3061\u306f',
          composing: TextRange.empty,
        ),
      );

      expect(handler.isComposing, isFalse);
      expect(doc.undoRedoManager.undoCount, beforeUndoCount + 1);
      expect(frag.text, 'Hello\u3053\u3093\u306b\u3061\u306f world');
    });

    test('IME backspace cancels preedit', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'a',
          composing: TextRange(start: 0, end: 1),
        ),
      );
      expect(handler.isComposing, isTrue);

      // Backspace all preedit text → composition cancelled.
      handler.updateEditingValue(
        const TextEditingValue(
          text: '',
          composing: TextRange.empty,
        ),
      );

      expect(handler.isComposing, isFalse);
      expect(handler.preeditText, '');
      expect(frag.text, 'Hello world'); // document unchanged
    });

    test('IME cancel does not create undo entry', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);
      final beforeUndoCount = doc.undoRedoManager.undoCount;

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'preedit',
          composing: TextRange(start: 0, end: 7),
        ),
      );
      expect(handler.isComposing, isTrue);

      // Cancel by sending empty text with invalid composing range.
      handler.updateEditingValue(
        const TextEditingValue(
          text: '',
          composing: TextRange.empty,
        ),
      );

      expect(handler.isComposing, isFalse);
      expect(doc.undoRedoManager.undoCount, beforeUndoCount);
      expect(frag.text, 'Hello world');
    });

    test('Cursor position during vs after composition', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 3);

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          composing: TextRange(start: 0, end: 3),
        ),
      );

      expect(doc.cursor.imeComposing, isTrue);
      expect(doc.cursor.anchorOffset, 3);
      expect(doc.cursor.focusOffset, 3);

      // After commit cursor should advance.
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          composing: TextRange.empty,
        ),
      );

      expect(doc.cursor.imeComposing, isFalse);
      expect(doc.cursor.anchorOffset, 6); // 3 + 'abc'.length
    });

    test('Preedit text never modifies JSON document until commit', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);
      final initialText = frag.text;
      final initialJson = doc.toJson();

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'preedit',
          composing: TextRange(start: 0, end: 7),
        ),
      );

      expect(frag.text, initialText);
      expect(doc.toJson(), initialJson);
      expect(doc.contentVersion, 0);
    });

    test('Preedit in list item', () {
      final list = FluentList(listType: 'bullet')
        ..items = [
          ListItem(bulletType: 'bullet', indexList: [1], children: [
            Paragraph(text: 'Item one'),
          ]),
        ];
      doc.loadContent(Root(nodes: [list]));

      final item = list.items.first;
      final para = item.children.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 3);

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'ime',
          composing: TextRange(start: 0, end: 3),
        ),
      );

      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, 'ime');
      expect(doc.cursor.imeComposing, isTrue);
    });

    test('Preedit in table cell', () {
      final cell = FluentCell(children: [Paragraph(text: 'Cell text')]);
      final row = FluentRow(cells: [cell]);
      final table = FluentTable(rows: [row]);
      doc.loadContent(Root(nodes: [table]));

      final para = cell.children.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 4);

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'table',
          composing: TextRange(start: 0, end: 5),
        ),
      );

      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, 'table');
      expect(doc.cursor.imeComposing, isTrue);
    });

    test('Undo after IME commit undoes entire committed phrase', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          composing: TextRange(start: 0, end: 3),
        ),
      );
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'abc',
          composing: TextRange.empty,
        ),
      );

      expect(frag.text, 'Helloabc world');

      doc.undo();
      final restoredPara = doc.content.nodes.first as Paragraph;
      final restoredFrag = restoredPara.fragments.first as Fragment;
      expect(restoredFrag.text, 'Hello world');
    });

    test('Perform action newline commits preedit and inserts paragraph', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      handler.updateEditingValue(
        const TextEditingValue(
          text: 'pre',
          composing: TextRange(start: 0, end: 3),
        ),
      );
      expect(handler.isComposing, isTrue);

      handler.performAction(TextInputAction.newline);
      expect(handler.isComposing, isFalse);
      expect(doc.content.nodes.length, 2);
    });
  });
}
