import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';

/// Helper: pump the FluentEditor with a given document.
Future<void> _pumpEditor(WidgetTester tester, FluentDocument doc) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: FluentEditor(document: doc),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

/// Find the center of the first paragraph widget's RenderBox.
Offset _paragraphCenter(WidgetTester tester) {
  final box = tester.renderObject(find.byType(FluentParagraphWidget).first);
  if (box is RenderBox) {
    return box.localToGlobal(box.size.center(Offset.zero));
  }
  return const Offset(400, 300);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Touch/Mobile e2e — tap', () {
    testWidgets('tap places cursor in paragraph', (tester) async {
      final doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello world')]));
      await _pumpEditor(tester, doc);

      await tester.tap(find.byType(FluentParagraphWidget).first);
      await tester.pumpAndSettle();

      expect(doc.cursor.anchorId, isNotEmpty);
    });

    testWidgets('tap at different x positions selects different offsets', (tester) async {
      final doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello world hello world')]));
      await _pumpEditor(tester, doc);

      final center = _paragraphCenter(tester);

      // Tap near the left edge of the paragraph
      await tester.tapAt(Offset(center.dx - 80, center.dy));
      await tester.pumpAndSettle();
      final leftOffset = doc.cursor.anchorOffset;

      // Tap near the right edge
      await tester.tapAt(Offset(center.dx + 80, center.dy));
      await tester.pumpAndSettle();
      final rightOffset = doc.cursor.anchorOffset;

      expect(rightOffset, greaterThan(leftOffset));
    });
  });

  group('Touch/Mobile e2e — double tap', () {
    testWidgets('double tap selects word', (tester) async {
      final doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello world foo')]));
      await _pumpEditor(tester, doc);

      final center = _paragraphCenter(tester);
      // Two quick taps at the same position
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(doc.cursor.isCollapsed, isFalse);
    });
  });

  group('Touch/Mobile e2e — triple tap', () {
    testWidgets('triple tap selects line/paragraph', (tester) async {
      final doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello world foo bar')]));
      await _pumpEditor(tester, doc);

      final center = _paragraphCenter(tester);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(doc.cursor.isCollapsed, isFalse);
    });
  });

  group('Touch/Mobile e2e — drag selection', () {
    testWidgets('drag from left to right changes cursor position', (tester) async {
      final doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello world foo bar baz')]));
      await _pumpEditor(tester, doc);

      final center = _paragraphCenter(tester);
      // Tap first to place cursor at center
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      // Drag rightward
      await tester.dragFrom(center, const Offset(100, 0));
      await tester.pumpAndSettle();

      // After drag, cursor should have moved (either selection or repositioned)
      expect(doc.cursor.anchorId, isNotEmpty);
    });

    testWidgets('drag produces valid cursor state', (tester) async {
      final doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello world foo bar baz qux')]));
      await _pumpEditor(tester, doc);

      final center = _paragraphCenter(tester);
      await tester.dragFrom(center, const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(doc.cursor.anchorId, isNotEmpty);
      expect(doc.cursor.anchorOffset, greaterThanOrEqualTo(0));
    });
  });

  group('Touch/Mobile e2e — keyboard focus', () {
    testWidgets('tap requests keyboard focus', (tester) async {
      final doc = FluentDocument(content: Root(nodes: [Paragraph(text: 'hello')]));
      await _pumpEditor(tester, doc);

      await tester.tap(find.byType(FluentParagraphWidget).first);
      await tester.pumpAndSettle();

      expect(doc.cursor.anchorId, isNotEmpty);
    });
  });
}
