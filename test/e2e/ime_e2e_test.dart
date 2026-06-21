import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/input/ime_handler.dart';

/// Helper: create a document with a single paragraph containing [text].
FluentDocument _docWithText(String text) {
  final p = Paragraph(text: text);
  final doc = FluentDocument(content: Root(nodes: [p]));
  doc.eventHandler.document = doc;
  doc.imeHandler.attachInput(doc);
  return doc;
}

/// Helper: get the first fragment of the first paragraph.
Fragment _firstFrag(FluentDocument doc) {
  final p = doc.content.nodes.first as Paragraph;
  return p.fragments.first as Fragment;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Reset the IME singleton between tests to prevent state leakage.
  setUp(() {
    FluentTextInputHandler().detachInput();
  });

  group('IME e2e — preedit isolation', () {
    test('document text unchanged during active composition', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);

      final handler = doc.imeHandler;
      handler.updateEditingValue(TextEditingValue(
        text: 'hello你好',
        selection: const TextSelection.collapsed(offset: 7),
        composing: const TextRange(start: 5, end: 7),
      ));

      expect(handler.isComposing, isTrue);
      expect(frag.text, 'hello');
      expect(handler.preeditText, '你好');
    });

    test('preedit in list item does not corrupt list structure', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final list = FluentList(listType: 'bullet');
      list.items = [
        ListItem(
          bulletType: 'bullet',
          indexList: [1],
          children: [Paragraph(text: 'item')],
        ),
      ];
      final doc = FluentDocument(content: Root(nodes: [list]));
      doc.eventHandler.document = doc;
      doc.imeHandler.attachInput(doc);

      final item = list.items.first;
      final p = item.children.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 4);

      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: 'item世',
        selection: const TextSelection.collapsed(offset: 5),
        composing: const TextRange(start: 4, end: 5),
      ));

      expect(doc.imeHandler.isComposing, isTrue);
      expect(frag.text, 'item');
      expect(list.items.length, 1);
    });
  });

  group('IME e2e — CJK multi-char composition + commit', () {
    test('commit inserts full composed text into fragment', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);

      // Simulate composition: type "你好" then commit
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: '你好',
        selection: const TextSelection.collapsed(offset: 2),
        composing: const TextRange(start: 0, end: 2),
      ));
      expect(doc.imeHandler.isComposing, isTrue);

      // Commit: platform sends value with no composing range
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: '你好',
        selection: const TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ));

      expect(doc.imeHandler.isComposing, isFalse);
      expect(frag.text, '你好');
      expect(doc.cursor.anchorOffset, 2);
    });

    test('commit replaces existing selection', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      // Select "world"
      doc.cursor.moveTo(frag.id, 6);
      doc.cursor.focusTo(frag.id, 11);

      // Start composition replacing selection — buffer includes full fragment text
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: 'hello 你好',
        selection: const TextSelection.collapsed(offset: 8),
        composing: const TextRange(start: 6, end: 8),
      ));

      // Commit
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: 'hello 你好',
        selection: const TextSelection.collapsed(offset: 8),
        composing: TextRange.empty,
      ));

      expect(frag.text, 'hello 你好');
      expect(doc.cursor.isCollapsed, isTrue);
    });
  });

  group('IME e2e — iOS backspace via delta', () {
    test('iOS placeholder deletion at fragment start triggers structural merge', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: 'world');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      doc.imeHandler.attachInput(doc);

      final frag2 = p2.fragments.first as Fragment;
      doc.cursor.moveTo(frag2.id, 0);

      // Simulate iOS deleting the zero-width placeholder
      doc.imeHandler.updateEditingValueWithDeltas([
        TextEditingDeltaDeletion(
          oldText: '\u200Bworld',
          deletedRange: const TextRange(start: 0, end: 1),
          selection: const TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      ]);

      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, contains('hello'));
      expect(doc.content.text, contains('world'));
    });

    test('iOS empty paragraph backspace merges with previous', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: '');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      doc.imeHandler.attachInput(doc);

      final frag2 = p2.fragments.first as Fragment;
      doc.cursor.moveTo(frag2.id, 0);

      doc.imeHandler.updateEditingValueWithDeltas([
        TextEditingDeltaDeletion(
          oldText: '\u200B',
          deletedRange: const TextRange(start: 0, end: 1),
          selection: const TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      ]);

      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'hello');
    });
  });

  group('IME e2e — iOS newline during composition', () {
    test('newline delta splits paragraph without text duplication', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);

      doc.imeHandler.updateEditingValueWithDeltas([
        TextEditingDeltaInsertion(
          oldText: 'hello',
          textInserted: '\n',
          insertionOffset: 5,
          selection: const TextSelection.collapsed(offset: 1),
          composing: TextRange.empty,
        ),
      ]);

      expect(doc.content.nodes.length, 2);
      expect((doc.content.nodes[0] as Paragraph).text, 'hello');
      expect((doc.content.nodes[1] as Paragraph).text, '');
    });
  });

  group('IME e2e — Android delta deletion', () {
    test('Android emoji deletion removes full grapheme', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('a😀b');
      final frag = _firstFrag(doc);
      // Cursor after the emoji: 'a' is 1 code unit, '😀' is 2 → offset 3
      doc.cursor.moveTo(frag.id, 3);

      // On Android, oldText reflects the IME buffer content.
      // Deleting at (2,3) removes the low surrogate; handler calls
      // executeHandleBackspace per grapheme, which is grapheme-aware.
      doc.imeHandler.updateEditingValueWithDeltas([
        TextEditingDeltaDeletion(
          oldText: 'a😀b',
          deletedRange: const TextRange(start: 2, end: 3),
          selection: const TextSelection.collapsed(offset: 2),
          composing: TextRange.empty,
        ),
      ]);

      expect(frag.text, 'ab');
    });

    test('Android zero-length deletion on empty fragment triggers merge', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: '');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      doc.imeHandler.attachInput(doc);

      final frag2 = p2.fragments.first as Fragment;
      doc.cursor.moveTo(frag2.id, 0);

      doc.imeHandler.updateEditingValueWithDeltas([
        TextEditingDeltaDeletion(
          oldText: '',
          deletedRange: const TextRange(start: 0, end: 0),
          selection: const TextSelection.collapsed(offset: 0),
          composing: TextRange.empty,
        ),
      ]);

      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'hello');
    });
  });

  group('IME e2e — Windows surrogate pair deletion', () {
    test('Windows deleting low surrogate expands to full emoji', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('x😀y');
      final frag = _firstFrag(doc);
      // text = "x😀y" = x(1) + 😀(2) + y(1) = 4 code units
      // Cursor after emoji (offset 3, before 'y')
      doc.cursor.moveTo(frag.id, 3);

      // Windows sends deletion of 1 code unit at position 2 (low surrogate)
      doc.imeHandler.updateEditingValueWithDeltas([
        TextEditingDeltaDeletion(
          oldText: 'x😀y',
          deletedRange: const TextRange(start: 2, end: 3),
          selection: const TextSelection.collapsed(offset: 2),
          composing: TextRange.empty,
        ),
      ]);

      expect(frag.text, 'xy');
    });
  });

  group('IME e2e — undo after IME commit', () {
    test('undo removes entire committed phrase in one step', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);

      // Compose "你好"
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: '你好',
        selection: const TextSelection.collapsed(offset: 2),
        composing: const TextRange(start: 0, end: 2),
      ));

      // Commit
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: '你好',
        selection: const TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ));

      expect(frag.text, '你好');

      // Single undo should remove the entire committed phrase
      expect(doc.canUndo, isTrue, reason: 'undo stack should have the commit delta');
      final undone = doc.undo();
      expect(undone, isTrue, reason: 'undo() should return true');
      // Re-fetch from document since undo replaces the node object
      expect(doc.content.text, '');
    });
  });

  group('IME e2e — cursor during composition', () {
    test('cursor is locked at composition start during preedit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('abc');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 3);

      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: 'abc你好',
        selection: const TextSelection.collapsed(offset: 5),
        composing: const TextRange(start: 3, end: 5),
      ));

      expect(doc.cursor.imeComposing, isTrue);
      expect(doc.cursor.anchorOffset, 3); // locked at composition start
    });

    test('cursor advances after commit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('abc');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 3);

      // Compose
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: 'abc你好',
        selection: const TextSelection.collapsed(offset: 5),
        composing: const TextRange(start: 3, end: 5),
      ));

      // Commit
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: 'abc你好',
        selection: const TextSelection.collapsed(offset: 5),
        composing: TextRange.empty,
      ));

      expect(doc.cursor.imeComposing, isFalse);
      expect(frag.text, 'abc你好');
      expect(doc.cursor.anchorOffset, 5); // advanced past committed text
    });
  });

  group('IME e2e — preedit shrink during composition (macOS)', () {
    test('shrinking preedit text does not commit partial text', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);

      // Type "你好世" — 3 chars in composition
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: '你好世',
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 0, end: 3),
      ));
      expect(doc.imeHandler.preeditText, '你好世');

      // User backspaces within the composition: preedit shrinks to "你好"
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: '你好',
        selection: const TextSelection.collapsed(offset: 2),
        composing: const TextRange(start: 0, end: 2),
      ));
      expect(doc.imeHandler.preeditText, '你好');
      expect(frag.text, ''); // still not committed

      // Commit "你好"
      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: '你好',
        selection: const TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ));
      expect(frag.text, '你好');
    });
  });

  group('IME e2e — commitIfComposing', () {
    test('commitIfComposing commits pending preedit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);

      doc.imeHandler.updateEditingValue(TextEditingValue(
        text: 'hello世',
        selection: const TextSelection.collapsed(offset: 6),
        composing: const TextRange(start: 5, end: 6),
      ));

      expect(doc.imeHandler.isComposing, isTrue);

      doc.imeHandler.commitIfComposing();

      expect(doc.imeHandler.isComposing, isFalse);
      expect(frag.text, 'hello世');
    });

    test('commitIfComposing is safe when not composing', () {
      final doc = _docWithText('hello');
      doc.imeHandler.commitIfComposing(); // should not throw
      expect(doc.content.text, 'hello');
    });
  });
}
