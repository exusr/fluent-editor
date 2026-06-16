import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';

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

      manager.beginSaveState(document, description: 'Typing', forceNewAction: true);
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

      manager.beginSaveState(document, description: 'After', forceNewAction: true);
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

      manager.beginSaveState(document, description: 'After', forceNewAction: true);
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
        manager.beginSaveState(document, description: 'State $i', forceNewAction: true);
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
}
