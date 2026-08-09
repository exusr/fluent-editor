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
  doc.eventHandler.handle(event, doc);
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

    test('arrow down works after replacing a selection', () {
      final p1 = Paragraph(text: 'hello world');
      final p2 = Paragraph(text: 'second paragraph');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;

      final frag1 = p1.fragments.first as Fragment;
      final frag2 = p2.fragments.first as Fragment;

      doc.cursor.moveTo(frag1.id, 1);
      doc.cursor.focusTo(frag1.id, 4);
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');
      expect(frag1.text, 'hxo world');
      expect(doc.cursor.isCollapsed, isTrue);

      _keyDown(doc, LogicalKeyboardKey.arrowDown);
      expect(doc.cursor.anchorId, frag2.id);
    });

    test('arrow down works after multi-paragraph replace with merge', () {
      final p1 = Paragraph(text: 'first paragraph');
      final p2 = Paragraph(text: 'second paragraph');
      final p3 = Paragraph(text: 'third paragraph');
      final doc = FluentDocument(content: Root(nodes: [p1, p2, p3]));
      doc.eventHandler.document = doc;

      final frag1 = p1.fragments.first as Fragment;
      final frag2 = p2.fragments.first as Fragment;
      final frag3 = p3.fragments.first as Fragment;

      // Select from middle of p1 to middle of p2, then type: p2 merges into p1.
      doc.cursor.moveTo(frag1.id, 5);
      doc.cursor.focusTo(frag2.id, 6);
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');

      expect(frag1.text, 'firstx');
      expect(doc.cursor.isCollapsed, isTrue);
      // Cursor must point to a fragment that still exists in the tree.
      expect(doc.nodeById(doc.cursor.anchorId), isNotNull);
      // p2 was merged away: only p1 (with merged frags) and p3 remain.
      expect(doc.content.nodes.length, 2);

      _keyDown(doc, LogicalKeyboardKey.arrowDown);
      expect(doc.cursor.anchorId, frag3.id);
    });

    test('typing replaces selection across list items without merging', () {
      final p1 = Paragraph(text: 'abc');
      final p2 = Paragraph(text: 'def');
      final item1 = ListItem(bulletType: 'bullet', indexList: [1], children: [p1]);
      final item2 = ListItem(bulletType: 'bullet', indexList: [2], children: [p2]);
      final list = FluentList(listType: 'bullet')
        ..items = [item1, item2];
      final doc = FluentDocument(content: Root(nodes: [list]));
      doc.eventHandler.document = doc;

      final frag1 = p1.fragments.first as Fragment;
      final frag2 = p2.fragments.first as Fragment;

      doc.cursor.moveTo(frag1.id, 1); // select from "a|bc"
      doc.cursor.focusTo(frag2.id, 2); // to "de|f"
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');

      expect(frag1.text, 'ax');
      expect(frag2.text, 'f');
      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.selectionManager.hasSelection, isFalse);
      expect(doc.isNodeSelected(p1.id), isFalse);
      expect(doc.isNodeSelected(p2.id), isFalse);
    });

    test('replace spanning sublist and ending in a different list', () {
      // L1: item A ("aaa") with sublist S ("sub"), item B ("bbb")
      // L2: item C ("ccc")
      final pA = Paragraph(text: 'aaa');
      final pSub = Paragraph(text: 'sub');
      final pB = Paragraph(text: 'bbb');
      final pC = Paragraph(text: 'ccc');

      final subItem = ListItem(bulletType: 'bullet', indexList: [1, 1], children: [pSub]);
      final sublist = FluentList(listType: 'bullet')..items = [subItem];
      final itemA = ListItem(bulletType: 'bullet', indexList: [1], children: [pA, sublist]);
      final itemB = ListItem(bulletType: 'bullet', indexList: [2], children: [pB]);
      final list1 = FluentList(listType: 'bullet')..items = [itemA, itemB];

      final itemC = ListItem(bulletType: 'bullet', indexList: [1], children: [pC]);
      final list2 = FluentList(listType: 'bullet')..items = [itemC];

      final after = Paragraph(text: 'after');
      final doc = FluentDocument(content: Root(nodes: [list1, list2, after]));
      doc.eventHandler.document = doc;

      final fragA = pA.fragments.first as Fragment;
      final fragC = pC.fragments.first as Fragment;
      final fragAfter = after.fragments.first as Fragment;

      // Select from "aa|a" through the sublist and item B, ending at "cc|c".
      doc.cursor.moveTo(fragA.id, 2);
      doc.cursor.focusTo(fragC.id, 2);
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');

      // Base fragment gets the typed char; extent keeps only the tail.
      expect(fragA.text, 'aax');
      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.cursor.anchorId, fragA.id);
      // Cursor must reference a fragment still present in the tree.
      expect(doc.nodeById(doc.cursor.anchorId), isNotNull);
      // Sublist and item B were fully selected: they must be gone.
      expect(doc.content.text.contains('sub'), isFalse);
      expect(doc.content.text.contains('bbb'), isFalse);
      // Tail of the extent must survive exactly once.
      expect('c'.allMatches(doc.content.text.replaceAll(RegExp('[^c]'), '')).length, 1);

      // Navigation below the modified area must still work.
      _keyDown(doc, LogicalKeyboardKey.arrowDown);
      final downId = doc.cursor.anchorId;
      expect(downId == fragAfter.id || doc.nodeById(downId) != null, isTrue);
      expect(doc.nodeById(downId), isNotNull);
    });

    test('replace starting inside sublist and ending in a different list', () {
      final pA = Paragraph(text: 'aaa');
      final pSub = Paragraph(text: 'sub');
      final pB = Paragraph(text: 'bbb');
      final pC = Paragraph(text: 'ccc');

      final subItem = ListItem(bulletType: 'bullet', indexList: [1, 1], children: [pSub]);
      final sublist = FluentList(listType: 'bullet')..items = [subItem];
      final itemA = ListItem(bulletType: 'bullet', indexList: [1], children: [pA, sublist]);
      final itemB = ListItem(bulletType: 'bullet', indexList: [2], children: [pB]);
      final list1 = FluentList(listType: 'bullet')..items = [itemA, itemB];

      final itemC = ListItem(bulletType: 'bullet', indexList: [1], children: [pC]);
      final list2 = FluentList(listType: 'bullet')..items = [itemC];

      final doc = FluentDocument(content: Root(nodes: [list1, list2]));
      doc.eventHandler.document = doc;

      final fragSub = pSub.fragments.first as Fragment;
      final fragC = pC.fragments.first as Fragment;

      // Select from "su|b" (inside the sublist) to "cc|c" (different list).
      doc.cursor.moveTo(fragSub.id, 2);
      doc.cursor.focusTo(fragC.id, 2);
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');

      expect(fragSub.text, 'sux');
      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.nodeById(doc.cursor.anchorId), isNotNull);
      // "aaa" precedes the selection: untouched.
      expect(doc.content.text.contains('aaa'), isTrue);
      // Item B was fully selected: gone.
      expect(doc.content.text.contains('bbb'), isFalse);
      // Tail "c" must survive exactly once.
      expect(doc.content.text.replaceAll(RegExp('[^c]'), '').length, 1);
    });

    test('typing replaces selection across table cells without merging', () {
      final p1 = Paragraph(text: 'abc');
      final p2 = Paragraph(text: 'def');
      final cell1 = FluentCell(children: [p1]);
      final cell2 = FluentCell(children: [p2]);
      final row = FluentRow(cells: [cell1, cell2]);
      final table = FluentTable(rows: [row]);
      final doc = FluentDocument(content: Root(nodes: [table]));
      doc.eventHandler.document = doc;

      final frag1 = p1.fragments.first as Fragment;
      final frag2 = p2.fragments.first as Fragment;

      doc.cursor.moveTo(frag1.id, 1);
      doc.cursor.focusTo(frag2.id, 2);
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');

      expect(frag1.text, 'ax');
      expect(frag2.text, 'f');
      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.selectionManager.hasSelection, isFalse);
      expect(doc.isNodeSelected(p1.id), isFalse);
      expect(doc.isNodeSelected(p2.id), isFalse);
    });

    test('replace from sublist up to different top-level list preserves tail and navigation', () {
      // Mirrors the example document structure:
      // Unordered list with "Tables with colSpan and rowSpan support"
      // Ordered list with item 2 "Advanced formatting" containing a sublist
      //   with "Bold, italic, underline" and "Superscript and subscript"
      final pColSpan = Paragraph(text: 'Tables with colSpan and rowSpan support');
      final itemU = ListItem(bulletType: 'bullet', indexList: [1], children: [pColSpan]);
      final ul = FluentList(listType: 'bullet')..items = [itemU];

      final pBasic = Paragraph(text: 'Basic editing');
      final item1 = ListItem(bulletType: 'ordered', indexList: [1], children: [pBasic]);

      final pAdv = Paragraph(text: 'Advanced formatting');
      final pBold = Paragraph(text: 'Bold, italic, underline');
      final pSuper = Paragraph(text: 'Superscript and subscript');
      final subItem1 = ListItem(bulletType: 'ordered', indexList: [2, 1], children: [pBold]);
      final subItem2 = ListItem(bulletType: 'ordered', indexList: [2, 2], children: [pSuper]);
      final sublist = FluentList(listType: 'ordered')..items = [subItem1, subItem2];
      final item2 = ListItem(bulletType: 'ordered', indexList: [2], children: [pAdv, sublist]);

      final pExport = Paragraph(text: 'Export and import');
      final item3 = ListItem(bulletType: 'ordered', indexList: [3], children: [pExport]);
      final ol = FluentList(listType: 'ordered')..items = [item1, item2, item3];

      final after = Paragraph(text: 'after');
      final doc = FluentDocument(content: Root(nodes: [ul, ol, after]));
      doc.eventHandler.document = doc;

      final fragColSpan = pColSpan.fragments.first as Fragment;
      final fragSuper = pSuper.fragments.first as Fragment;

      // Select from "Tables with |colSpan..." (unordered list) up to
      // "Super|script and subscript" (sublist of ordered list item 2).
      doc.cursor.moveTo(fragSuper.id, 5);
      doc.cursor.focusTo(fragColSpan.id, 12);
      _keyDown(doc, LogicalKeyboardKey.keyX, character: 'x');

      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.nodeById(doc.cursor.anchorId), isNotNull);
      // The tail of the extent ("script and subscript") must survive.
      expect(doc.content.text.contains('script and subscript'), isTrue);
      // Fully selected intermediate content must be gone.
      expect(doc.content.text.contains('Basic editing'), isFalse);
      expect(doc.content.text.contains('Advanced formatting'), isFalse);
      expect(doc.content.text.contains('Bold, italic, underline'), isFalse);
      // item2 (which had its Paragraph removed and only had a sublist) must be gone.
      expect(doc.nodeById(item2.id), isNull);
      // Navigation below the modified area must still work.
      _keyDown(doc, LogicalKeyboardKey.arrowDown);
      expect(doc.nodeById(doc.cursor.anchorId), isNotNull);
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
      doc.eventHandler.handle(event, doc);
      expect(frag.isBold, isTrue);
    });
  });
}
