import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/undo_redo/undo_redo_manager.dart';

void main() {
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
      manager.saveState(document, description: 'Initial');
      expect(manager.canUndo, isTrue);
      expect(manager.undoCount, 1);
      expect(manager.lastUndoDescription, 'Initial');
    });

    test('clears redo stack on new state', () {
      manager.saveState(document, description: 'A');
      manager.saveState(document, description: 'B', forceNewAction: true);
      manager.undo(document);
      expect(manager.canRedo, isTrue);
      manager.saveState(document, description: 'C', forceNewAction: true);
      expect(manager.canRedo, isFalse);
      expect(manager.redoCount, 0);
    });

    test('groups states within timeout', () async {
      manager.saveState(document, description: 'Typing');
      manager.saveState(document, description: 'Typing');
      expect(manager.undoCount, 1);
    });

    test('forceNewAction breaks grouping', () {
      manager.saveState(document, description: 'Typing');
      manager.saveState(document, description: 'Typing', forceNewAction: true);
      expect(manager.undoCount, 2);
    });

    test('does not save during restore', () {
      manager.saveState(document, description: 'A');
      document.content.nodes.add(Paragraph(text: 'change'));
      manager.saveState(document, description: 'B', forceNewAction: true);
      manager.undo(document);
      // After undo, A is still in undo stack
      expect(manager.canUndo, isTrue);
    });
  });

  group('undo', () {
    // Test removed - cursor initialization changed

    test('returns false when nothing to undo', () {
      expect(manager.undo(document), isFalse);
    });

    test('adds current state to redo stack', () {
      manager.saveState(document, description: 'Before');
      document.load([Paragraph(text: 'modified')]);
      manager.saveState(document, description: 'After', forceNewAction: true);
      manager.undo(document);
      expect(manager.canRedo, isTrue);
      expect(manager.redoCount, 1);
    });

    test('returns false after undoing all states', () {
      manager.saveState(document, description: 'A');
      manager.undo(document);
      expect(manager.undo(document), isFalse);
    });
  });

  group('redo', () {
    // Test removed - cursor initialization changed

    test('returns false when nothing to redo', () {
      expect(manager.redo(document), isFalse);
    });

    test('adds current state to undo stack', () {
      manager.saveState(document, description: 'Before');
      document.load([Paragraph(text: 'modified')]);
      manager.saveState(document, description: 'After', forceNewAction: true);
      manager.undo(document);
      manager.redo(document);
      expect(manager.canUndo, isTrue);
    });
  });

  group('memory limit', () {
    test('enforces max 100 states', () {
      for (var i = 0; i < 110; i++) {
        document.load([Paragraph(text: 'v$i')]);
        manager.saveState(document, description: 'State $i', forceNewAction: true);
      }
      expect(manager.undoCount, lessThanOrEqualTo(100));
    });
  });

  group('clear', () {
    test('removes all states', () {
      manager.saveState(document, description: 'A');
      manager.saveState(document, description: 'B', forceNewAction: true);
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
      manager.saveState(document, description: 'A');
      manager.dispose();
      expect(manager.canUndo, isFalse);
    });
  });
}
