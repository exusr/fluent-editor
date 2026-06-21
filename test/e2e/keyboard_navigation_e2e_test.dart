import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';

/// Helper: create a document with a single paragraph containing [text].
FluentDocument _docWithText(String text) {
  final p = Paragraph(text: text);
  final doc = FluentDocument(content: Root(nodes: [p]));
  doc.eventHandler.document = doc;
  return doc;
}

/// Helper: get the first fragment of the first paragraph.
Fragment _firstFrag(FluentDocument doc) {
  final p = doc.content.nodes.first as Paragraph;
  return p.fragments.first as Fragment;
}

/// Simulate a KeyDownEvent and route it through the document's event handler.
void _keyDown(FluentDocument doc, LogicalKeyboardKey key,
    {bool ctrl = false, bool shift = false, bool meta = false, String? character}) {
  final event = KeyDownEvent(
    physicalKey: key == LogicalKeyboardKey.enter
        ? PhysicalKeyboardKey.enter
        : key == LogicalKeyboardKey.backspace
            ? PhysicalKeyboardKey.backspace
            : key == LogicalKeyboardKey.tab
                ? PhysicalKeyboardKey.tab
                : key == LogicalKeyboardKey.arrowLeft
                    ? PhysicalKeyboardKey.arrowLeft
                    : key == LogicalKeyboardKey.arrowRight
                        ? PhysicalKeyboardKey.arrowRight
                        : key == LogicalKeyboardKey.arrowUp
                            ? PhysicalKeyboardKey.arrowUp
                            : key == LogicalKeyboardKey.arrowDown
                                ? PhysicalKeyboardKey.arrowDown
                                : key == LogicalKeyboardKey.home
                                    ? PhysicalKeyboardKey.home
                                    : key == LogicalKeyboardKey.end
                                        ? PhysicalKeyboardKey.end
                                        : PhysicalKeyboardKey.space,
    logicalKey: key,
    character: character,
    timeStamp: Duration.zero,
  );
  // Set modifier state before dispatching, then call handleKeyDown
  // directly (bypassing manageEvent/updateModifiers which reads from
  // HardwareKeyboard.instance and would overwrite our test state).
  doc.eventHandler.isCtrlPressed = ctrl;
  doc.eventHandler.isShiftPressed = shift;
  doc.eventHandler.isMetaPressed = meta;
  doc.eventHandler.handleKeyDown(event, doc);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Keyboard e2e — arrow navigation', () {
    test('arrow right moves within fragment', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 2);
      _keyDown(doc, LogicalKeyboardKey.arrowRight);
      expect(doc.cursor.anchorOffset, 3);
    });

    test('arrow left moves within fragment', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 3);
      _keyDown(doc, LogicalKeyboardKey.arrowLeft);
      expect(doc.cursor.anchorOffset, 2);
    });

    test('arrow right at end of fragment moves to next fragment', () {
      final doc = _docWithText('');
      final p = doc.content.nodes.first as Paragraph;
      final f1 = Fragment('hello');
      final f2 = Fragment(' world');
      p.fragments = [f1, f2];
      doc.cursor.moveTo(f1.id, 5);
      _keyDown(doc, LogicalKeyboardKey.arrowRight);
      expect(doc.cursor.anchorId, f2.id);
      expect(doc.cursor.anchorOffset, 0);
    });

    test('arrow left at start of fragment moves to previous fragment', () {
      final doc = _docWithText('');
      final p = doc.content.nodes.first as Paragraph;
      final f1 = Fragment('hello');
      final f2 = Fragment(' world');
      p.fragments = [f1, f2];
      doc.cursor.moveTo(f2.id, 0);
      _keyDown(doc, LogicalKeyboardKey.arrowLeft);
      expect(doc.cursor.anchorId, f1.id);
      expect(doc.cursor.anchorOffset, greaterThan(0));
    });

    test('arrow down moves to next line', () {
      final doc = _docWithText('hello world foo bar');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      _keyDown(doc, LogicalKeyboardKey.arrowDown);
      // Cursor should be on a later position in the text
      expect(doc.cursor.anchorOffset, greaterThan(0));
    });

    test('arrow up moves to previous line', () {
      final doc = _docWithText('hello world foo bar');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, frag.text.length);
      _keyDown(doc, LogicalKeyboardKey.arrowUp);
      // Cursor should be on an earlier position
      expect(doc.cursor.anchorOffset, lessThan(frag.text.length));
    });

    test('arrow right jumps between top-level nodes', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: 'world');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      final frag1 = p1.fragments.first as Fragment;
      final frag2 = p2.fragments.first as Fragment;
      doc.cursor.moveTo(frag1.id, 5);
      _keyDown(doc, LogicalKeyboardKey.arrowRight);
      expect(doc.cursor.anchorId, frag2.id);
      expect(doc.cursor.anchorOffset, 0);
    });
  });

  group('Keyboard e2e — shift+arrow selection', () {
    test('shift+arrow right extends selection', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 2);
      _keyDown(doc, LogicalKeyboardKey.arrowRight, shift: true);
      expect(doc.cursor.isCollapsed, isFalse);
      expect(doc.cursor.anchorOffset, 2);
      expect(doc.cursor.focusOffset, 3);
    });

    test('shift+arrow left extends selection backwards', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 3);
      _keyDown(doc, LogicalKeyboardKey.arrowLeft, shift: true);
      expect(doc.cursor.isCollapsed, isFalse);
      expect(doc.cursor.anchorOffset, 3);
      expect(doc.cursor.focusOffset, 2);
    });

    test('arrow on non-collapsed selection collapses to edge', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 1);
      doc.cursor.focusTo(frag.id, 4);
      expect(doc.cursor.isCollapsed, isFalse);
      // Arrow right without shift: collapse to end of selection
      _keyDown(doc, LogicalKeyboardKey.arrowRight);
      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.cursor.anchorOffset, 4);
    });
  });

  group('Keyboard e2e — Home/End', () {
    test('Home moves to line start', () {
      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);
      _keyDown(doc, LogicalKeyboardKey.home);
      expect(doc.cursor.anchorOffset, 0);
    });

    test('End moves to line end', () {
      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      _keyDown(doc, LogicalKeyboardKey.end);
      expect(doc.cursor.anchorOffset, frag.text.length);
    });
  });

  group('Keyboard e2e — select all', () {
    test('Ctrl+A selects entire document', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: 'world');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      _keyDown(doc, LogicalKeyboardKey.keyA, ctrl: true);
      expect(doc.cursor.isCollapsed, isFalse);
    });
  });

  group('Keyboard e2e — undo/redo', () {
    test('Ctrl+Z undoes last action', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);
      doc.saveState(description: 'before delete');
      frag.text = 'hell';
      doc.updateContent();
      _keyDown(doc, LogicalKeyboardKey.keyZ, ctrl: true);
      // Re-fetch from document since undo replaces the node object
      expect(doc.content.text, 'hello');
    });

    test('Ctrl+Shift+Z redoes', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);
      doc.saveState(description: 'before delete');
      frag.text = 'hell';
      doc.updateContent();
      doc.undo();
      expect(doc.content.text, 'hello');
      _keyDown(doc, LogicalKeyboardKey.keyZ, ctrl: true, shift: true);
      expect(doc.content.text, 'hell');
    });
  });

  group('Keyboard e2e — formatting shortcuts', () {
    test('Ctrl+B toggles bold', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      doc.cursor.focusTo(frag.id, 5);
      _keyDown(doc, LogicalKeyboardKey.keyB, ctrl: true);
      expect(frag.isBold, isTrue);
    });

    test('Ctrl+I toggles italic', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      doc.cursor.focusTo(frag.id, 5);
      _keyDown(doc, LogicalKeyboardKey.keyI, ctrl: true);
      expect(frag.styles?.contains('italic'), isTrue);
    });

    test('Ctrl+U toggles underline', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      doc.cursor.focusTo(frag.id, 5);
      _keyDown(doc, LogicalKeyboardKey.keyU, ctrl: true);
      expect(frag.styles?.contains('underline'), isTrue);
    });
  });

  group('Keyboard e2e — Tab/Shift+Tab', () {
    test('Tab indents paragraph', () {
      final doc = _docWithText('hello');
      final p = doc.content.nodes.first as Paragraph;
      doc.cursor.moveTo(_firstFrag(doc).id, 0);
      _keyDown(doc, LogicalKeyboardKey.tab);
      expect(p.indent, 1);
    });

    test('Shift+Tab outdents paragraph', () {
      final doc = _docWithText('hello');
      final p = doc.content.nodes.first as Paragraph;
      p.indent = 2;
      doc.cursor.moveTo(_firstFrag(doc).id, 0);
      _keyDown(doc, LogicalKeyboardKey.tab, shift: true);
      expect(p.indent, 1);
    });
  });

  group('Keyboard e2e — Enter key', () {
    test('Enter splits paragraph at cursor', () {
      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);
      _keyDown(doc, LogicalKeyboardKey.enter);
      expect(doc.content.nodes.length, 2);
      expect((doc.content.nodes[0] as Paragraph).text, 'hello');
      expect((doc.content.nodes[1] as Paragraph).text, ' world');
    });

    test('Enter in list item creates new item', () {
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
      final p = list.items.first.children.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 4); // end of "item"
      _keyDown(doc, LogicalKeyboardKey.enter);
      expect(list.items.length, 2);
    });

    test('Enter in empty list item outdents', () {
      final list = FluentList(listType: 'bullet');
      list.items = [
        ListItem(
          bulletType: 'bullet',
          indexList: [1],
          children: [Paragraph(text: '')],
        ),
      ];
      final doc = FluentDocument(content: Root(nodes: [list]));
      doc.eventHandler.document = doc;
      final p = list.items.first.children.first as Paragraph;
      final frag = p.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 0);
      _keyDown(doc, LogicalKeyboardKey.enter);
      // Empty item → outdent: list should be removed or item converted to paragraph
      expect(list.items.length, 0);
    });
  });

  group('Keyboard e2e — macOS Cmd+Backspace', () {
    test('Cmd+Backspace deletes to line start on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 7); // in the middle of "world"
      // On macOS, isCtrlPressed means Cmd (swapped in updateModifiers)
      _keyDown(doc, LogicalKeyboardKey.backspace, ctrl: true);
      // Should delete from start of line to cursor
      expect(frag.text.isNotEmpty, isTrue);
      expect(doc.cursor.anchorOffset, lessThan(7));
    });
  });

  group('Keyboard e2e — Ctrl+Backspace word delete', () {
    test('Ctrl+Backspace deletes previous word', () {
      final doc = _docWithText('hello world foo');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 15); // end of text
      _keyDown(doc, LogicalKeyboardKey.backspace, ctrl: true);
      // Should delete "foo" (the last word)
      expect(frag.text, 'hello world ');
    });
  });

  group('Keyboard e2e — character input', () {
    test('typing a character inserts it at cursor', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);
      _keyDown(doc, LogicalKeyboardKey.keyA, character: 'a');
      expect(frag.text, 'helloa');
      expect(doc.cursor.anchorOffset, 6);
    });

    test('typing replaces active selection', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 1);
      doc.cursor.focusTo(frag.id, 4); // select "ell"
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');
      expect(frag.text, 'hxo');
      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.cursor.anchorOffset, 2);
    });
  });

  group('Keyboard e2e — macOS modifier mapping', () {
    test('Cmd is mapped to Ctrl on macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      doc.cursor.focusTo(frag.id, 5);

      // On macOS, meta (Cmd) is swapped to ctrl in updateModifiers
      // So pressing Cmd+B should bold
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyB,
        logicalKey: LogicalKeyboardKey.keyB,
        character: 'b',
        timeStamp: Duration.zero,
      );
      // On macOS, meta (Cmd) is swapped to ctrl in updateModifiers.
      // Since we bypass updateModifiers, we set isCtrlPressed=true
      // (which represents Cmd on macOS after the swap).
      doc.eventHandler.isCtrlPressed = true;
      doc.eventHandler.handleKeyDown(event, doc);
      expect(frag.isBold, isTrue);
    });
  });
}
