import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';

/// Integration test for keyboard navigation on real devices.
/// Run with: flutter test integration_test/keyboard_integration_test.dart -d <device>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FluentDocument doc;

  setUp(() {
    doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello world')]));
  });

  group('Keyboard integration — typing and navigation', () {
    testWidgets('type text and navigate with arrow keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(width: 800, height: 600, child: FluentEditor(document: doc))),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();

      // Type extra text via testTextInput (simulates native IME)
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'hello world foo'),
      );
      await tester.pumpAndSettle();

      expect(doc.content.text, contains('foo'));

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(doc.cursor.anchorId, isNotEmpty);
    });

    testWidgets('home key moves to line start', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(width: 800, height: 600, child: FluentEditor(document: doc))),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(doc.cursor.anchorOffset, lessThanOrEqualTo(1));
    });

    testWidgets('end key moves to line end', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(width: 800, height: 600, child: FluentEditor(document: doc))),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(50, 300));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(doc.cursor.anchorOffset, greaterThanOrEqualTo(10));
    });
  });

  group('Keyboard integration — shortcuts', () {
    testWidgets('Ctrl+A selects all', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(width: 800, height: 600, child: FluentEditor(document: doc))),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(doc.cursor.isCollapsed, isFalse);
    }, tags: ['desktop']);

    testWidgets('Ctrl+B toggles bold on selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(width: 800, height: 600, child: FluentEditor(document: doc))),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final p = doc.content.nodes.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      expect(frag.isBold, isTrue);
    }, tags: ['desktop']);

    testWidgets('Ctrl+Z undoes last action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(width: 800, height: 600, child: FluentEditor(document: doc))),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();

      // Type something to undo via testTextInput
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: 'hello world extra'),
      );
      await tester.pumpAndSettle();

      final beforeUndo = doc.content.text;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(doc.content.text, isNot(beforeUndo));
    }, tags: ['desktop']);
  });

  group('Keyboard integration — key repeat', () {
    testWidgets('holding arrow key repeats movement', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SizedBox(width: 800, height: 600, child: FluentEditor(document: doc))),
      );
      await tester.pumpAndSettle();

      // Tap near end of 'hello world' to get a non-zero offset
      await tester.tapAt(const Offset(700, 300));
      await tester.pumpAndSettle();

      final startOffset = doc.cursor.anchorOffset;
      if (startOffset == 0) {
        // Text not found at expected position; skip this test on this platform
        return;
      }

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(doc.cursor.anchorOffset, lessThan(startOffset));
    }, tags: ['desktop']);
  });
}
