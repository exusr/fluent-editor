import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/core/types.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';

void main() {
  group('CursorOffset', () {
    late FluentDocument document;

    setUp(() {
      document = FluentDocument(
        content: Root(nodes: [
          Paragraph(text: 'hello'),
          Paragraph(text: 'world'),
        ]),
      );
    });

    test('constructs with id and offset', () {
      final co = CursorOffset(id: 'abc', offset: 3);
      expect(co.id, 'abc');
      expect(co.offset, 3);
    });

    test('localToGlobal does nothing when id is a top-level node', () {
      final rootId = document.content.nodes.first.id;
      final co = CursorOffset(id: rootId, offset: 2);
      co.localToGlobal(document, forward: true);
      // When id matches a top-level node, the method returns early
      expect(co.id, rootId);
      expect(co.offset, 2);
    });

    test('localToGlobal converts fragment offset to global', () {
      final paragraph = document.content.nodes.first as Paragraph;
      final fragment = paragraph.fragments.first as Fragment;
      final co = CursorOffset(id: fragment.id, offset: 2);
      co.localToGlobal(document, forward: true);
      expect(co.id, paragraph.id);
      expect(co.offset, 2);
    });
  });

  group('FNodeRange', () {
    test('constructs with node and parent', () {
      final node = Paragraph(text: 'hello');
      final parent = Root(nodes: [node]);
      final range = FNodeRange(node: node, parent: parent);
      expect(range.node, node);
      expect(range.parent, parent);
    });

    test('constructs with null parent', () {
      final node = Paragraph(text: 'hello');
      final range = FNodeRange(node: node);
      expect(range.node, node);
      expect(range.parent, isNull);
    });
  });

  group('FragmentRange', () {
    test('constructs with all fields', () {
      final fragment = Fragment('hello');
      final parent = Paragraph(text: 'hello');
      final range = FragmentRange(
        fragment: fragment,
        parent: parent,
        offset: 1,
        focus: 4,
      );
      expect(range.fragment, fragment);
      expect(range.parent, parent);
      expect(range.offset, 1);
      expect(range.focus, 4);
    });
  });
}
