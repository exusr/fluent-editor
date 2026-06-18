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

    test('macOS buffer-sync preedit shrinks during active composition syncs fragment', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Start composition on macOS: the fragment mirrors the full buffer
      // (preedit included) because the OS draws its own composition underline.
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'Hello nyuuryokuworld',
          composing: TextRange(start: 6, end: 15),
        ),
      );
      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, 'nyuuryoku');
      expect(frag.text, 'Hello nyuuryokuworld');

      // While still composing, macOS sends a shorter suggestion.
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'Hello nyuryokuworld',
          composing: TextRange(start: 6, end: 14),
        ),
      );

      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, 'nyuryoku');
      // No stale characters remain.
      expect(frag.text, 'Hello nyuryokuworld');
    });

    test('macOS buffer-sync commit with shorter suggestion clears ghost preedit', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Start composition on macOS: the full buffer is the fragment text
      // merged with the preedit. Cursor is at position 5 (after "Hello").
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'Hello nyuuryokuworld',
          composing: TextRange(start: 6, end: 15),
        ),
      );
      expect(handler.isComposing, isTrue);
      expect(handler.preeditText, 'nyuuryoku');

      // Commit with a shorter suggestion (e.g. predictive text corrected
      // "nyuuryoku" to "nyuryoku"). The full buffer now contains the
      // committed text merged with surrounding fragment text.
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'Hello nyuryokuworld',
          composing: TextRange.empty,
        ),
      );

      expect(handler.isComposing, isFalse);
      // The fragment must contain exactly the committed text with no
      // trailing ghost characters from the longer preedit.
      expect(frag.text, 'Hello nyuryokuworld');
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

    test('iOS buffer-sync backspace at fragment start merges with previous paragraph', () {
      doc.loadContent(Root(nodes: [
        Paragraph(text: 'First'),
        Paragraph(text: 'Second'),
      ]));

      final firstPara = doc.content.nodes[0] as Paragraph;
      final secondPara = doc.content.nodes[1] as Paragraph;
      final secondFrag = secondPara.fragments.first as Fragment;
      doc.cursor.moveTo(secondFrag.id, 0);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // iOS sends a deletion of the first character even though the cursor
      // is at the start of the fragment. The editor must treat this as a
      // structural backspace and merge with the previous paragraph.
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'econd',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );

      expect(doc.content.nodes.length, 1);
      final mergedPara = doc.content.nodes[0] as Paragraph;
      final mergedFrag = mergedPara.fragments.first as Fragment;
      expect(mergedFrag.text, 'FirstSecond');
    });

    test('cursor offset clamped when larger than fragment text length', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      frag.text = 'short';
      doc.cursor.moveTo(frag.id, 10);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // currentTextEditingValue must not assert even when the cursor is
      // temporarily out of bounds (offset 10 > text length 5).
      final value = handler.currentTextEditingValue!;
      expect(value.text, 'short');
      expect(value.selection.baseOffset, 5);
      expect(value.selection.extentOffset, 5);

      // syncImeBufferToFragment must also complete without throwing.
      expect(() => handler.syncImeBufferToFragment(), returnsNormally);
    });

    test('cursor offset clamped when negative', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      frag.text = 'text';
      doc.cursor.moveTo(frag.id, -3);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final value = handler.currentTextEditingValue!;
      expect(value.selection.baseOffset, 0);
      expect(value.selection.extentOffset, 0);
    });

    test('Android backspace on emoji deletes only the emoji, not previous char', () {
      doc.loadContent(Root(nodes: [Paragraph(text: 'a\u{1F600}')]));
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 3); // cursor after emoji

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Android IME may send a delta that deletes only the first code unit
      // (high surrogate) of the emoji. The handler must not call backspace
      // twice, because executeHandleBackspace is already grapheme-aware.
      handler.updateEditingValueWithDeltas([
        TextEditingDeltaDeletion(
          oldText: 'a\u{1F600}',
          deletedRange: const TextRange(start: 1, end: 2),
          selection: const TextSelection.collapsed(offset: 1),
          composing: TextRange.empty,
        ),
      ]);

      expect(frag.text, 'a');
    });

    test('Windows buffer-sync backspace on low surrogate deletes full emoji', () {
      doc.loadContent(Root(nodes: [Paragraph(text: 'a\u{1F600}')]));
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 3);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Windows IME may send a delta that deletes only the second code unit
      // (low surrogate) of the emoji. The handler must expand the range so
      // the whole surrogate pair is removed, avoiding orphaned surrogates.
      handler.updateEditingValueWithDeltas([
        TextEditingDeltaDeletion(
          oldText: 'a\u{1F600}',
          deletedRange: const TextRange(start: 2, end: 3),
          selection: const TextSelection.collapsed(offset: 2),
          composing: TextRange.empty,
        ),
      ]);

      expect(frag.text, 'a');
    });

    test('iOS newline during composition does not duplicate text in new paragraph', () {
      final para = doc.content.nodes.first as Paragraph;
      final frag = para.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 5);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Start composition on iOS: full buffer is "Hello preworld"
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'Hello preworld',
          composing: TextRange(start: 6, end: 9),
        ),
      );
      expect(handler.isComposing, isTrue);

      handler.performAction(TextInputAction.newline);

      expect(handler.isComposing, isFalse);
      expect(doc.content.nodes.length, 2);

      // After commit, first paragraph contains "Hello pre"
      final firstPara = doc.content.nodes[0] as Paragraph;
      final firstFrag = firstPara.fragments.first as Fragment;
      expect(firstFrag.text, 'Hello pre');

      // Second paragraph should contain only "world", not duplicated text
      final secondPara = doc.content.nodes[1] as Paragraph;
      final secondFrag = secondPara.fragments.first as Fragment;
      expect(secondFrag.text, 'world');
    });

    test('iOS buffer-sync backspace empties sole paragraph fragment and merges', () {
      doc.loadContent(Root(nodes: [
        Paragraph(text: 'First'),
        Paragraph(text: 'Second'),
      ]));

      final secondPara = doc.content.nodes[1] as Paragraph;
      final secondFrag = secondPara.fragments.first as Fragment;
      doc.cursor.moveTo(secondFrag.id, secondFrag.text.length);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Simulate iOS replacement delta that deletes the entire "Second" text.
      handler.updateEditingValueWithDeltas([
        TextEditingDeltaReplacement(
          oldText: 'Second',
          replacementText: '',
          replacedRange: const TextRange(start: 0, end: 6),
          selection: const TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      ]);

      // The second paragraph should be removed and merged with the first.
      expect(doc.content.nodes.length, 1);
      final mergedPara = doc.content.nodes[0] as Paragraph;
      final mergedFrag = mergedPara.fragments.first as Fragment;
      expect(mergedFrag.text, 'First');
    });

    test('iOS backspace on already-empty fragment triggers structural merge', () {
      doc.loadContent(Root(nodes: [
        Paragraph(text: 'First'),
        Paragraph(text: ''),
      ]));

      final secondPara = doc.content.nodes[1] as Paragraph;
      final secondFrag = secondPara.fragments.first as Fragment;
      doc.cursor.moveTo(secondFrag.id, 0);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Simulate the exact condition that reaches updateEditingValue after
      // the delta path: empty text, empty fragment, cursor at 0.
      // Without the fix the "skip our own echo" check would return early
      // and the structural backspace would never happen.
      handler.updateEditingValue(
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );

      // The empty second paragraph should be removed.
      expect(doc.content.nodes.length, 1);
      final mergedPara = doc.content.nodes[0] as Paragraph;
      final mergedFrag = mergedPara.fragments.first as Fragment;
      expect(mergedFrag.text, 'First');
    });

    test('Android zero-length deletion on empty fragment triggers structural merge', () {
      doc.loadContent(Root(nodes: [
        Paragraph(text: 'First'),
        Paragraph(text: 'Second'),
      ]));

      final secondPara = doc.content.nodes[1] as Paragraph;
      final secondFrag = secondPara.fragments.first as Fragment;
      secondFrag.text = '';
      doc.cursor.moveTo(secondFrag.id, 0);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Android may send a zero-length deletion when the buffer is already empty.
      handler.updateEditingValueWithDeltas([
        TextEditingDeltaReplacement(
          oldText: '',
          replacementText: '',
          replacedRange: const TextRange(start: 0, end: 0),
          selection: const TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      ]);

      // The empty second paragraph should be removed.
      expect(doc.content.nodes.length, 1);
      final mergedPara = doc.content.nodes[0] as Paragraph;
      final mergedFrag = mergedPara.fragments.first as Fragment;
      expect(mergedFrag.text, 'First');
    });

    test('iOS updateEditingValue snaps cursor when pointing to removed fragment', () {
      doc.loadContent(Root(nodes: [
        Paragraph(text: 'First'),
        Paragraph(text: 'Second'),
      ]));

      final secondPara = doc.content.nodes[1] as Paragraph;
      final secondFrag = secondPara.fragments.first as Fragment;
      doc.cursor.moveTo(secondFrag.id, 0);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Remove the second paragraph manually to simulate rapid backspace
      // leaving the cursor on a stale fragment id.
      doc.content.nodes.removeAt(1);
      doc.invalidateNodeIndex();

      // Now send a buffer-sync update. The handler must snap the cursor
      // to a valid stop before diffing.
      handler.updateEditingValue(
        const TextEditingValue(
          text: 'First',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      // Cursor should point to the first paragraph, not the removed one.
      final currentNode = doc.nodeById(doc.cursor.anchorId);
      expect(currentNode, isNotNull);
      expect(currentNode, isA<Fragment>());
      expect((currentNode as Fragment).text, 'First');
    });
  });
}
