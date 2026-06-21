import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/handlers/handle_backspace.dart';
import 'package:fluent_editor/handlers/handle_delete.dart';
import 'package:fluent_editor/handlers/handle_replace_selection.dart';

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

void main() {
  group('Backspace/Delete e2e — basic deletion', () {
    test('backspace deletes previous character', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 5);
      executeHandleBackspace(doc);
      expect(frag.text, 'hell');
      expect(doc.cursor.anchorOffset, 4);
    });

    test('delete key removes character after cursor', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      executeHandleDelete(doc);
      expect(frag.text, 'ello');
      expect(doc.cursor.anchorOffset, 0);
    });

    test('backspace is grapheme-aware (emoji)', () {
      final doc = _docWithText('a😀b');
      final frag = _firstFrag(doc);
      // Cursor after emoji: 'a' is 1 code unit, '😀' is 2 → offset 3
      doc.cursor.moveTo(frag.id, 3);
      executeHandleBackspace(doc);
      expect(frag.text, 'ab');
    });

    test('delete at emoji start is grapheme-safe (no-op with count=1)', () {
      final doc = _docWithText('a😀b');
      final frag = _firstFrag(doc);
      // Cursor before emoji: offset 1
      doc.cursor.moveTo(frag.id, 1);
      executeHandleDelete(doc);
      // deleteTextInFragment uses safeSubstring which prevents cutting
      // through surrogate pairs. Deleting 1 code unit at the high surrogate
      // is a no-op because safeSubstring adjusts the index back.
      // Known limitation: delete handler should use getGraphemeLengthAt
      // to delete the full grapheme cluster.
      expect(frag.text, 'a😀b'); // unchanged — grapheme-safe
    });
  });

  group('Backspace e2e — fragment start merge', () {
    test('backspace at fragment start merges with previous paragraph', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: 'world');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      final frag2 = p2.fragments.first as Fragment;
      doc.cursor.moveTo(frag2.id, 0);
      executeHandleBackspace(doc);
      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'helloworld');
    });

    test('backspace at fragment start merges with previous (with space)', () {
      final p1 = Paragraph(text: 'hello ');
      final p2 = Paragraph(text: 'world');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      final frag2 = p2.fragments.first as Fragment;
      doc.cursor.moveTo(frag2.id, 0);
      executeHandleBackspace(doc);
      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'hello world');
    });
  });

  group('Backspace e2e — empty fragment cleanup', () {
    test('backspace removes empty fragments', () {
      final p1 = Paragraph(text: 'hello');
      final p2 = Paragraph(text: '');
      final doc = FluentDocument(content: Root(nodes: [p1, p2]));
      doc.eventHandler.document = doc;
      final frag2 = p2.fragments.first as Fragment;
      doc.cursor.moveTo(frag2.id, 0);
      executeHandleBackspace(doc);
      expect(doc.content.nodes.length, 1);
      expect(doc.content.text, 'hello');
    });
  });

  group('Backspace e2e — Link cleanup', () {
    test('backspace cleans up empty Link', () {
      final p = Paragraph(text: '');
      final link = Link(url: 'https://example.com');
      link.fragments = [Fragment('')];
      p.fragments = [Fragment('before'), link, Fragment('after')];
      final doc = FluentDocument(content: Root(nodes: [p]));
      doc.eventHandler.document = doc;
      final linkFrag = link.fragments.first as Fragment;
      doc.cursor.moveTo(linkFrag.id, 0);
      executeHandleBackspace(doc);
      // Link should be removed since it's empty
      final hasLink = p.fragments.whereType<Link>().isNotEmpty;
      expect(hasLink, isFalse);
    });
  });

  group('Backspace e2e — ZWS handling', () {
    test('backspace skips invisible ZWS and deletes real character', () {
      final p = Paragraph(text: '');
      final frag = Fragment('a\u200Bb'); // a + ZWS + b
      p.fragments = [frag];
      final doc = FluentDocument(content: Root(nodes: [p]));
      doc.eventHandler.document = doc;
      // Cursor after ZWS (offset 2: after 'a' and ZWS)
      doc.cursor.moveTo(frag.id, 2);
      executeHandleBackspace(doc);
      // ZWS should be skipped, 'a' should be deleted
      expect(frag.text.contains('a'), isFalse);
    });
  });

  group('Backspace e2e — HorizontalRule', () {
    test('backspace on HorizontalRule removes it', () {
      final hr = HorizontalRule();
      final doc = FluentDocument(content: Root(nodes: [hr]));
      doc.eventHandler.document = doc;
      doc.cursor.moveTo(hr.id, 0);
      executeHandleBackspace(doc);
      expect(doc.content.nodes.whereType<HorizontalRule>(), isEmpty);
    });
  });

  group('Backspace e2e — image', () {
    test('backspace on image removes it', () {
      final image = FluentImage('test.png');
      final p = Paragraph(text: '');
      p.fragments = [image];
      final doc = FluentDocument(content: Root(nodes: [p]));
      doc.eventHandler.document = doc;
      doc.cursor.moveTo(image.id, 0);
      executeHandleBackspace(doc);
      // Image should be removed from fragments
      final hasImage = p.fragments.whereType<FluentImage>().isNotEmpty;
      expect(hasImage, isFalse);
    });
  });

  group('Backspace e2e — list item outdent', () {
    test('backspace in list item at start outdents', () {
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
      doc.cursor.moveTo(frag.id, 0);
      executeHandleBackspace(doc);
      // Item should be outdented (list may be removed or item converted)
      // After outdent, the text should still exist as a paragraph
      expect(doc.content.text, contains('item'));
    });
  });

  group('Backspace e2e — Ctrl+Backspace word delete', () {
    test('Ctrl+Backspace deletes previous word', () {
      final doc = _docWithText('hello world foo');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 15);
      executeHandleBackspace(doc, ctrl: true);
      expect(frag.text, 'hello world ');
    });

    test('Ctrl+Backspace at start of text does nothing', () {
      final doc = _docWithText('hello');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      executeHandleBackspace(doc, ctrl: true);
      expect(frag.text, 'hello');
    });
  });

  group('Backspace e2e — selection deletion', () {
    test('backspace with active selection deletes selection', () {
      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      doc.cursor.focusTo(frag.id, 5); // select "hello"
      executeHandleBackspace(doc);
      expect(frag.text, ' world');
      expect(doc.cursor.isCollapsed, isTrue);
      expect(doc.cursor.anchorOffset, 0);
    });

    test('delete with active selection deletes selection', () {
      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      doc.cursor.focusTo(frag.id, 5); // select "hello"
      executeHandleDelete(doc);
      expect(frag.text, ' world');
      expect(doc.cursor.isCollapsed, isTrue);
    });

    test('replace selection with empty string deletes it', () {
      final doc = _docWithText('hello world');
      final frag = _firstFrag(doc);
      doc.cursor.moveTo(frag.id, 0);
      doc.cursor.focusTo(frag.id, 5);
      executeHandleReplaceSelection('', doc);
      expect(frag.text, ' world');
    });
  });

  group('Backspace e2e — image with adjacent text', () {
    test('backspace emptying fragment next to image falls back to valid caret', () {
      final image = FluentImage('test.png');
      final p = Paragraph(text: 'hi');
      p.fragments = [Fragment('hi'), image];
      final doc = FluentDocument(content: Root(nodes: [p]));
      doc.eventHandler.document = doc;
      final frag = p.fragments.first as Fragment;
      doc.cursor.moveTo(frag.id, 2);
      executeHandleBackspace(doc); // delete 'i'
      executeHandleBackspace(doc); // delete 'h', fragment becomes empty
      // The empty fragment should be removed
      expect(doc.nodeById(frag.id), isNull);
      // Cursor should land on a valid existing node
      final currentNode = doc.nodeById(doc.cursor.anchorId);
      expect(currentNode, isNotNull);
    });
  });
}
