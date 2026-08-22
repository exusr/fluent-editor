import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/input/ime_handler.dart';

FluentDocument _docWithText(String text) {
  final p = Paragraph(text: text);
  final doc = FluentDocument(content: Root(nodes: [p]));
  doc.eventHandler.document = doc;
  doc.imeHandler.attachInput(doc);
  return doc;
}

Fragment _firstFrag(FluentDocument doc) {
  final p = doc.content.nodes.first as Paragraph;
  return p.fragments.first as Fragment;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Linux IME Execution Branch Tests', () {
    setUp(() {
      FluentTextInputHandler().detachInput();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      FluentTextInputHandler().detachInput();
    });

    test('Linux updateEditingValue handles preedit lifecycle and commit', () {
      final doc = _docWithText('Hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);

      // Start preedit composition on Linux
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello世',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 5, end: 6),
      ));

      expect(doc.imeHandler.isComposing, isTrue);
      expect(doc.imeHandler.preeditText, '世');

      // Update preedit with candidate
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello世界',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 5, end: 7),
      ));

      expect(doc.imeHandler.isComposing, isTrue);
      expect(doc.imeHandler.preeditText, '世界');

      // Finish composition
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello世界',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange.empty,
      ));

      expect(doc.imeHandler.isComposing, isFalse);
      expect(frag.text, 'Hello世界');
    });

    test('Linux updateEditingValue CJK composition replaces active selection and clears selection rendering', () {
      final doc = _docWithText('Hello World');
      final frag = _firstFrag(doc);
      final p = doc.content.nodes.first as Paragraph;
      // Select "World" (offset 6 to 11)
      doc.cursor.anchorId = frag.id;
      doc.cursor.anchorOffset = 6;
      doc.cursor.focusId = frag.id;
      doc.cursor.focusOffset = 11;
      doc.selectionManager.startSelection(p.id, frag.id, 6);
      doc.selectionManager.updateFocus(p.id, frag.id, 11);
      expect(doc.selectionManager.hasSelection, isTrue);

      // Start CJK composition replacing selected text "World"
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello 漢',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 6, end: 7),
      ));

      expect(doc.imeHandler.isComposing, isTrue);
      expect(doc.imeHandler.preeditText, '漢');
      expect(frag.text, 'Hello '); // "World" was deleted upon preedit start!

      // Commit CJK composition
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello 漢字',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange.empty,
      ));

      expect(doc.imeHandler.isComposing, isFalse);
      expect(frag.text, 'Hello 漢字');
      expect(doc.selectionManager.hasSelection, isFalse); // Selection rendering cleared!
    });

    test('Linux CJK replace does not delete characters from unaffected text after commit', () {
      final doc = _docWithText('Hello World, testing Linux IME replace!');
      final frag = _firstFrag(doc);
      final p = doc.content.nodes.first as Paragraph;

      // Select "World" (offset 6 to 11)
      doc.cursor.anchorId = frag.id;
      doc.cursor.anchorOffset = 6;
      doc.cursor.focusId = frag.id;
      doc.cursor.focusOffset = 11;
      doc.selectionManager.startSelection(p.id, frag.id, 6);
      doc.selectionManager.updateFocus(p.id, frag.id, 11);

      // Start preedit with CJK character
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello 世界, testing Linux IME replace!',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange(start: 6, end: 8),
      ));

      expect(doc.imeHandler.isComposing, isTrue);
      expect(doc.imeHandler.preeditText, '世界');
      expect(frag.text, 'Hello , testing Linux IME replace!'); // Only "World" was removed!

      // Commit preedit
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello 世界, testing Linux IME replace!',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange.empty,
      ));

      // Post-commit buffer sync update from Linux engine
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello , testing Linux IME replace!',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      ));

      expect(frag.text, 'Hello 世界, testing Linux IME replace!');
    });

    test('Linux CJK replace commitment is retained during post-commit platform sync', () {
      final doc = _docWithText('Hello World');
      final frag = _firstFrag(doc);
      final p = doc.content.nodes.first as Paragraph;
      // Select "World" (offset 6 to 11)
      doc.cursor.anchorId = frag.id;
      doc.cursor.anchorOffset = 6;
      doc.cursor.focusId = frag.id;
      doc.cursor.focusOffset = 11;

      // 1. Start preedit
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello 漢',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 6, end: 7),
      ));

      expect(doc.imeHandler.isComposing, isTrue);

      // 2. Commit preedit with "漢字"
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello 漢字',
        selection: TextSelection.collapsed(offset: 8),
        composing: TextRange.empty,
      ));

      expect(frag.text, 'Hello 漢字');

      // 3. Post-commit platform sync carrying stale platform buffer "Hello "
      doc.imeHandler.updateEditingValue(const TextEditingValue(
        text: 'Hello ',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange.empty,
      ));

      expect(frag.text, 'Hello 漢字');
    });

    test('Linux updateEditingValueWithDeltas CJK selection replace commits preedit on standalone Deletion delta', () {
      final doc = _docWithText('Hello World');
      final frag = _firstFrag(doc);
      final p = doc.content.nodes.first as Paragraph;

      // Select "World" (offset 6 to 11)
      doc.cursor.anchorId = frag.id;
      doc.cursor.anchorOffset = 6;
      doc.cursor.focusId = frag.id;
      doc.cursor.focusOffset = 11;
      doc.selectionManager.startSelection(p.id, frag.id, 6);
      doc.selectionManager.updateFocus(p.id, frag.id, 11);

      // 1. Start preedit with deltas
      final startDeltas = <TextEditingDelta>[
        TextEditingDeltaInsertion(
          oldText: 'Hello World',
          textInserted: '日本',
          insertionOffset: 6,
          selection: const TextSelection.collapsed(offset: 8),
          composing: const TextRange(start: 6, end: 8),
        ),
      ];
      doc.imeHandler.updateEditingValueWithDeltas(startDeltas);
      expect(doc.imeHandler.isComposing, isTrue);
      expect(doc.imeHandler.preeditText, '日本');
      expect(frag.text, 'Hello '); // "World" was deleted

      // 2. Fcitx/IBus standalone preedit-clear Deletion delta before commit
      final clearPreeditDeltas = <TextEditingDelta>[
        TextEditingDeltaDeletion(
          oldText: 'Hello 日本',
          deletedRange: const TextRange(start: 6, end: 8),
          selection: const TextSelection.collapsed(offset: 6),
          composing: TextRange.empty,
        ),
      ];
      doc.imeHandler.updateEditingValueWithDeltas(clearPreeditDeltas);

      // Candidate "日本" MUST be committed to document text!
      expect(doc.imeHandler.isComposing, isFalse);
      expect(frag.text, 'Hello 日本');
    });

    test('Linux updateEditingValueWithDeltas CJK composition replaces active selection and clears selection rendering', () {
      final doc = _docWithText('Hello World');
      final frag = _firstFrag(doc);
      final p = doc.content.nodes.first as Paragraph;
      // Select "World" (offset 6 to 11)
      doc.cursor.anchorId = frag.id;
      doc.cursor.anchorOffset = 6;
      doc.cursor.focusId = frag.id;
      doc.cursor.focusOffset = 11;
      doc.selectionManager.startSelection(p.id, frag.id, 6);
      doc.selectionManager.updateFocus(p.id, frag.id, 11);
      expect(doc.selectionManager.hasSelection, isTrue);

      final deltas = <TextEditingDelta>[
        TextEditingDeltaInsertion(
          oldText: 'Hello World',
          textInserted: '漢',
          insertionOffset: 6,
          selection: const TextSelection.collapsed(offset: 7),
          composing: const TextRange(start: 6, end: 7),
        ),
      ];

      doc.imeHandler.updateEditingValueWithDeltas(deltas);

      expect(doc.imeHandler.isComposing, isTrue);
      expect(doc.imeHandler.preeditText, '漢');
      expect(frag.text, 'Hello '); // Selected text "World" was deleted!

      // Commit composition via NonTextUpdate
      final commitDeltas = <TextEditingDelta>[
        TextEditingDeltaNonTextUpdate(
          oldText: 'Hello 漢字',
          selection: const TextSelection.collapsed(offset: 8),
          composing: TextRange.empty,
        ),
      ];

      doc.imeHandler.updateEditingValueWithDeltas(commitDeltas);

      expect(doc.imeHandler.isComposing, isFalse);
      expect(frag.text, 'Hello 漢');
      expect(doc.selectionManager.hasSelection, isFalse); // Selection rendering cleared!
    });

    test('Linux updateEditingValueWithDeltas handles insertion deltas', () {
      final doc = _docWithText('Test');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 4);

      final deltas = <TextEditingDelta>[
        TextEditingDeltaInsertion(
          oldText: 'Test',
          textInserted: '!',
          insertionOffset: 4,
          selection: const TextSelection.collapsed(offset: 5),
          composing: TextRange.empty,
        ),
      ];

      doc.imeHandler.updateEditingValueWithDeltas(deltas);

      expect(frag.text, 'Test!');
    });

    test('Linux updateEditingValueWithDeltas batchEndsComposing commits composition', () {
      final doc = _docWithText('Base');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 4);

      final deltas = <TextEditingDelta>[
        TextEditingDeltaInsertion(
          oldText: 'Base',
          textInserted: 'A',
          insertionOffset: 4,
          selection: const TextSelection.collapsed(offset: 5),
          composing: const TextRange(start: 4, end: 5),
        ),
        TextEditingDeltaNonTextUpdate(
          oldText: 'BaseA',
          selection: const TextSelection.collapsed(offset: 5),
          composing: TextRange.empty,
        ),
      ];

      doc.imeHandler.updateEditingValueWithDeltas(deltas);

      expect(doc.imeHandler.isComposing, isFalse);
      expect(frag.text, 'BaseA');
    });

    test('Linux updateEditingValueWithDeltas deletion delta handles character removal', () {
      final doc = _docWithText('RemoveMe');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 8);

      final deltas = <TextEditingDelta>[
        TextEditingDeltaDeletion(
          oldText: 'RemoveMe',
          deletedRange: const TextRange(start: 6, end: 8),
          selection: const TextSelection.collapsed(offset: 6),
          composing: TextRange.empty,
        ),
      ];

      doc.imeHandler.updateEditingValueWithDeltas(deltas);

      expect(frag.text, 'Remove');
    });

    test('Linux currentTextEditingValue returns Linux platform editing state', () {
      final doc = _docWithText('Sample');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 3);

      final editingValue = doc.imeHandler.currentTextEditingValue;

      expect(editingValue, isNotNull);
      expect(editingValue!.text, 'Sample');
      expect(editingValue.selection, const TextSelection.collapsed(offset: 3));
    });
  });
}
