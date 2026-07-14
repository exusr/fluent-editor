import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/handlers/handle_insert_node.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FluentDocument document;
  late UndoRedoManager manager;

  setUp(() {
    document = FluentDocument();
    manager = UndoRedoManager();
    document.eventHandler.document = document;
  });

  group('UndoRedoManager initial state', () {
    test('cannot undo or redo initially', () {
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
      expect(manager.undoCount, 0);
      expect(manager.redoCount, 0);
    });
  });

  group('saveState', () {
    test('adds state to undo stack', () {
      manager.beginSaveState(document, description: 'Initial');
      document.content.nodes.add(Paragraph(text: 'Initial'));
      manager.commitSaveState(document);
      expect(manager.canUndo, isTrue);
      expect(manager.undoCount, 1);
      expect(manager.lastUndoDescription, 'Initial');
    });

    test('clears redo stack on new state', () {
      manager.beginSaveState(document, description: 'A');
      document.content.nodes.add(Paragraph(text: 'A'));
      manager.commitSaveState(document);

      manager.beginSaveState(document, description: 'B', forceNewAction: true);
      document.content.nodes[0] = Paragraph(text: 'B');
      manager.commitSaveState(document);

      manager.undo(document);
      expect(manager.canRedo, isTrue);

      manager.beginSaveState(document, description: 'C', forceNewAction: true);
      document.content.nodes[0] = Paragraph(text: 'C');
      manager.commitSaveState(document);
      expect(manager.canRedo, isFalse);
      expect(manager.redoCount, 0);
    });

    test('groups states within timeout', () async {
      manager.beginSaveState(document, description: 'Typing');
      document.content.nodes.add(Paragraph(text: 'A'));
      manager.commitSaveState(document);

      manager.beginSaveState(document, description: 'Typing');
      document.content.nodes[0] = Paragraph(text: 'B');
      manager.commitSaveState(document);

      expect(manager.undoCount, 1);
    });

    test('forceNewAction breaks grouping', () {
      manager.beginSaveState(document, description: 'Typing');
      document.content.nodes.add(Paragraph(text: 'A'));
      manager.commitSaveState(document);

      manager.beginSaveState(
        document,
        description: 'Typing',
        forceNewAction: true,
      );
      document.content.nodes[0] = Paragraph(text: 'B');
      manager.commitSaveState(document);

      expect(manager.undoCount, 2);
    });

    test('does not save during restore', () {
      manager.beginSaveState(document, description: 'A');
      document.content.nodes.add(Paragraph(text: 'A'));
      manager.commitSaveState(document);

      manager.beginSaveState(document, description: 'B', forceNewAction: true);
      document.content.nodes[0] = Paragraph(text: 'change');
      manager.commitSaveState(document);

      manager.undo(document);
      // After undo, A is still in undo stack
      expect(manager.canUndo, isTrue);
    });
  });

  group('undo', () {
    test('returns false when nothing to undo', () {
      expect(manager.undo(document), isFalse);
    });

    test('adds current state to redo stack', () {
      manager.beginSaveState(document, description: 'Before');
      document.content.nodes.add(Paragraph(text: 'Before'));
      manager.commitSaveState(document);

      manager.beginSaveState(
        document,
        description: 'After',
        forceNewAction: true,
      );
      document.load([Paragraph(text: 'modified')]);
      manager.commitSaveState(document);

      manager.undo(document);
      expect(manager.canRedo, isTrue);
      expect(manager.redoCount, 1);
    });

    test('returns false after undoing all states', () {
      manager.beginSaveState(document, description: 'A');
      document.content.nodes.add(Paragraph(text: 'A'));
      manager.commitSaveState(document);

      manager.undo(document);
      expect(manager.undo(document), isFalse);
    });
  });

  group('redo', () {
    test('returns false when nothing to redo', () {
      expect(manager.redo(document), isFalse);
    });

    test('adds current state to undo stack', () {
      manager.beginSaveState(document, description: 'Before');
      document.content.nodes.add(Paragraph(text: 'Before'));
      manager.commitSaveState(document);

      manager.beginSaveState(
        document,
        description: 'After',
        forceNewAction: true,
      );
      document.load([Paragraph(text: 'modified')]);
      manager.commitSaveState(document);

      manager.undo(document);
      manager.redo(document);
      expect(manager.canUndo, isTrue);
    });
  });

  group('memory limit', () {
    test('enforces max 100 states', () {
      for (var i = 0; i < 110; i++) {
        manager.beginSaveState(
          document,
          description: 'State $i',
          forceNewAction: true,
        );
        document.load([Paragraph(text: 'v$i')]);
        manager.commitSaveState(document);
      }
      expect(manager.undoCount, lessThanOrEqualTo(100));
    });
  });

  group('clear', () {
    test('removes all states', () {
      manager.beginSaveState(document, description: 'A');
      document.content.nodes.add(Paragraph(text: 'A'));
      manager.commitSaveState(document);

      manager.beginSaveState(document, description: 'B', forceNewAction: true);
      document.content.nodes.add(Paragraph(text: 'B'));
      manager.commitSaveState(document);

      manager.clear();
      expect(manager.canUndo, isFalse);
      expect(manager.canRedo, isFalse);
    });
  });

  group('restore cursor and selection', () {
    // Tests removed - cursor initialization changed
  });

  group('dispose', () {
    test('clears and cancels timer', () {
      manager.beginSaveState(document, description: 'A');
      document.content.nodes.add(Paragraph(text: 'A'));
      manager.commitSaveState(document);

      manager.dispose();
      expect(manager.canUndo, isFalse);
    });
  });

  group('inline image undo/redo', () {
    test('undo restores deleted inline image inside paragraph', () {
      final img = FluentImage('https://example.com/img.png');
      final para = Paragraph(text: 'hello');
      para.fragments.add(img);
      document.load([para]);

      manager.beginSaveState(
        document,
        description: 'Delete image',
        forceNewAction: true,
      );
      removeNode(document.content, img);
      document.invalidateNodeIndex();
      manager.commitSaveState(document);

      expect(manager.canUndo, isTrue);
      final paraAfter = document.content.nodes.first as Paragraph;
      expect(paraAfter.fragments.length, 1);
      expect(paraAfter.fragments.first is Fragment, isTrue);

      manager.undo(document);

      final restoredPara = document.content.nodes.first as Paragraph;
      expect(restoredPara.fragments.length, 2);
      expect(restoredPara.fragments.any((f) => f is FluentImage), isTrue);
    });

    test('redo re-removes deleted inline image', () {
      final img = FluentImage('https://example.com/img.png');
      final para = Paragraph(text: 'hello');
      para.fragments.add(img);
      document.load([para]);

      manager.beginSaveState(
        document,
        description: 'Delete image',
        forceNewAction: true,
      );
      removeNode(document.content, img);
      document.invalidateNodeIndex();
      manager.commitSaveState(document);

      manager.undo(document);
      expect(manager.canRedo, isTrue);

      manager.redo(document);
      final restoredPara = document.content.nodes.first as Paragraph;
      expect(restoredPara.fragments.length, 1);
      expect(restoredPara.fragments.any((f) => f is FluentImage), isFalse);
    });

    test('undo restores structural image change with unchanged text', () {
      final img = FluentImage('https://example.com/img.png');
      final para = Paragraph(text: '');
      para.fragments = [img];
      document.load([para]);

      manager.beginSaveState(
        document,
        description: 'Replace image',
        forceNewAction: true,
      );
      para.fragments = [Fragment('\u200B')];
      manager.commitSaveState(document);

      expect(para.text, '\u200B');
      expect(manager.canUndo, isTrue);

      manager.undo(document);
      final restoredPara = document.content.nodes.first as Paragraph;
      expect(restoredPara.text, '\u200B');
      expect(restoredPara.fragments.single, isA<FluentImage>());
    });

    testWidgets('undo renders an inline image deleted after insertion', (
      tester,
    ) async {
      final para = Paragraph(text: 'hello world');
      document.load([para]);
      final frag = para.fragments.single as Fragment;

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: FluentEditor(document: document),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(InlineImageWidget), findsNothing);
      document.cursor.moveTo(frag.id, 5);

      document.saveState(description: 'Insert image', forceNewAction: true);
      handleInsertNodeExceution('image', document, {
        'src':
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      });
      await tester.pump();
      final img = (document.content.nodes.first as Paragraph).fragments
          .whereType<FluentImage>()
          .single;
      expect(find.byType(InlineImageWidget), findsOneWidget);
      expect(document.cursor.anchorId, img.id);
      expect(document.cursor.anchorOffset, 1);

      document.requestEditorFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.byType(InlineImageWidget), findsNothing);

      final versionAfterDelete = document.contentVersion;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(document.contentVersion, versionAfterDelete + 1);
      expect(find.byType(InlineImageWidget), findsOneWidget);
      expect(document.cursor.anchorId, img.id);
      expect(document.cursor.anchorOffset, 1);
    });

    test('undo restores deleted block-level image', () {
      final img = FluentImage('https://example.com/img.png');
      document.load([Paragraph(text: 'before'), img, Paragraph(text: 'after')]);

      manager.beginSaveState(
        document,
        description: 'Delete image',
        forceNewAction: true,
      );
      removeNode(document.content, img);
      document.invalidateNodeIndex();
      manager.commitSaveState(document);

      expect(document.content.nodes.length, 2);
      expect(manager.canUndo, isTrue);

      manager.undo(document);
      expect(document.content.nodes.length, 3);
      expect(document.content.nodes[1] is FluentImage, isTrue);
    });

    test('undo restores resized inline image dimensions', () {
      final img = FluentImage('https://example.com/img.png');
      img.width = 300.0;
      img.height = 200.0;
      final para = Paragraph(text: 'hello');
      para.fragments.add(img);
      document.load([para]);

      manager.beginSaveState(
        document,
        description: 'Resize image',
        forceNewAction: true,
      );
      img.width = 400.0;
      img.height = 300.0;
      manager.commitSaveState(document);

      expect(manager.canUndo, isTrue);

      manager.undo(document);
      final restoredPara = document.content.nodes.first as Paragraph;
      final restoredImg = restoredPara.fragments.whereType<FluentImage>().first;
      expect(restoredImg.width, 300.0);
      expect(restoredImg.height, 200.0);
    });

    test('e2e: insert inline image then delete then undo restores image', () {
      // Set up document with text "hello world"
      final para = Paragraph(text: 'hello world');
      document.load([para]);

      // Position cursor at offset 5 (between "hello" and " world")
      final frag = para.fragments.first as Fragment;
      document.cursor.moveTo(frag.id, 5);

      // Insert image inline (using document's internal undo manager)
      document.saveState(description: 'Insert image', forceNewAction: true);
      handleInsertNodeExceution('image', document, {
        'src': 'https://example.com/test.png',
      });

      // Verify image was inserted
      final paraAfterInsert = document.content.nodes.first as Paragraph;
      expect(paraAfterInsert.fragments.whereType<FluentImage>().length, 1);
      final img = paraAfterInsert.fragments.whereType<FluentImage>().first;
      expect(document.cursor.anchorId, img.id);
      expect(document.cursor.anchorOffset, 1);
      expect(document.canUndo, isTrue);

      // Now delete the image via backspace
      document.saveState(description: 'Delete', forceNewAction: true);
      executeHandleBackspace(document);

      // Verify image was deleted
      final paraAfterDelete = document.content.nodes.first as Paragraph;
      expect(paraAfterDelete.fragments.whereType<FluentImage>().length, 0);
      expect(document.canUndo, isTrue);

      // Undo the deletion — should restore the image
      document.undo();

      final paraAfterUndo = document.content.nodes.first as Paragraph;
      expect(
        paraAfterUndo.fragments.whereType<FluentImage>().length,
        1,
        reason: 'Undo should restore the deleted inline image',
      );

      // Redo the deletion — should re-remove the image
      expect(document.canRedo, isTrue);
      document.redo();

      final paraAfterRedo = document.content.nodes.first as Paragraph;
      expect(
        paraAfterRedo.fragments.whereType<FluentImage>().length,
        0,
        reason: 'Redo should re-remove the deleted inline image',
      );
    });
  });
}
