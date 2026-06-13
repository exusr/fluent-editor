import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';

void main() {
  group('collectLeafFragments', () {
    test('collects from simple paragraph', () {
      final p = Paragraph(text: 'hello');
      final leaves = FragmentOperations.collectLeafFragments(p);
      expect(leaves.length, 1);
      expect(leaves.first.text, 'hello');
    });

    test('collects from paragraph with multiple fragments', () {
      final p = Paragraph();
      p.fragments = [Fragment('hello'), Fragment(' world')];
      final leaves = FragmentOperations.collectLeafFragments(p);
      expect(leaves.length, 2);
      expect(leaves[0].text, 'hello');
      expect(leaves[1].text, ' world');
    });

    test('collects through Link transparently', () {
      final link = Link(url: 'https://x.com', text: 'link');
      final leaves = FragmentOperations.collectLeafFragments(link);
      expect(leaves.length, 1);
      expect(leaves.first.text, 'link');
    });

    test('collects through nested structures', () {
      final root = Root(nodes: [
        Paragraph(text: 'a'),
        Link(url: 'https://x.com', text: 'b'),
      ]);
      final leaves = FragmentOperations.collectLeafFragments(root);
      expect(leaves.length, 2);
      expect(leaves[0].text, 'a');
      expect(leaves[1].text, 'b');
    });

    test('skips InlineContainerNode children', () {
      final table = FluentTable(rows: [
        FluentRow(cells: [
          FluentCell(children: [Paragraph(text: 'hello')]),
        ]),
      ]);
      final leaves = FragmentOperations.collectLeafFragments(table);
      expect(leaves.length, 1);
      expect(leaves.first.text, 'hello');
    });
  });

  group('cloneFragment', () {
    test('clones text and styles', () {
      final f = Fragment('hello', styles: ['bold'], color: '#FF0000');
      final clone = FragmentOperations.cloneFragment(f);
      expect(clone.text, 'hello');
      expect(clone.styles, contains('bold'));
      expect(clone.color, '#FF0000');
      expect(clone.id, isNot(equals(f.id)));
    });

    test('clones with override text', () {
      final f = Fragment('hello', styles: ['bold']);
      final clone = FragmentOperations.cloneFragment(f, text: 'world');
      expect(clone.text, 'world');
      expect(clone.styles, contains('bold'));
    });

    test('clones empty styles as empty list', () {
      final f = Fragment('hello');
      final clone = FragmentOperations.cloneFragment(f);
      expect(clone.styles, isEmpty);
    });
  });

  group('createFragmentWithPendingStyles', () {
    test('creates fragment with document pending styles', () {
      final doc = FluentDocument();
      doc.pendingStyles = ['bold', 'italic'];
      doc.pendingFontFamily = 'Roboto';
      doc.pendingFontSize = 18.0;
      doc.pendingColor = '#FF0000';
      doc.pendingHighlightColor = '#FFFF00';

      final f = FragmentOperations.createFragmentWithPendingStyles(doc, 'hello');
      expect(f.text, 'hello');
      expect(f.styles, containsAll(['bold', 'italic']));
      expect(f.fontFamily, 'Roboto');
      expect(f.fontSize, 18.0);
      expect(f.color, '#FF0000');
      expect(f.highlightColor, '#FFFF00');
    });
  });

  group('insertTextInFragment', () {
    test('inserts at beginning', () {
      final f = Fragment('world');
      final ok = FragmentOperations.insertTextInFragment(f, 0, 'hello ');
      expect(ok, isTrue);
      expect(f.text, 'hello world');
    });

    test('inserts at end', () {
      final f = Fragment('hello');
      final ok = FragmentOperations.insertTextInFragment(f, 5, ' world');
      expect(ok, isTrue);
      expect(f.text, 'hello world');
    });

    test('inserts in middle', () {
      final f = Fragment('helloworld');
      final ok = FragmentOperations.insertTextInFragment(f, 5, ' ');
      expect(ok, isTrue);
      expect(f.text, 'hello world');
    });

    test('returns false for negative offset', () {
      final f = Fragment('hello');
      final ok = FragmentOperations.insertTextInFragment(f, -1, 'x');
      expect(ok, isFalse);
      expect(f.text, 'hello');
    });

    test('returns false for offset beyond length', () {
      final f = Fragment('hello');
      final ok = FragmentOperations.insertTextInFragment(f, 10, 'x');
      expect(ok, isFalse);
      expect(f.text, 'hello');
    });
  });

  group('deleteTextInFragment', () {
    test('deletes single character in middle', () {
      final f = Fragment('hello');
      final ok = FragmentOperations.deleteTextInFragment(f, 1, count: 1);
      expect(ok, isTrue);
      expect(f.text, 'hllo');
    });

    test('deletes multiple characters', () {
      final f = Fragment('hello world');
      final ok = FragmentOperations.deleteTextInFragment(f, 5, count: 6);
      expect(ok, isTrue);
      expect(f.text, 'hello');
    });

    test('returns false for negative offset', () {
      final f = Fragment('hello');
      final ok = FragmentOperations.deleteTextInFragment(f, -1);
      expect(ok, isFalse);
      expect(f.text, 'hello');
    });

    test('returns false for count beyond length', () {
      final f = Fragment('hello');
      final ok = FragmentOperations.deleteTextInFragment(f, 3, count: 5);
      expect(ok, isFalse);
      expect(f.text, 'hello');
    });
  });

  group('splitFragment', () {
    test('splits at middle', () {
      final f = Fragment('hello world');
      final result = FragmentOperations.splitFragment(f, 5);
      expect(result.left.text, 'hello');
      expect(result.right.text, ' world');
    });

    test('splits at beginning', () {
      final f = Fragment('hello');
      final result = FragmentOperations.splitFragment(f, 0);
      expect(result.left.text, '');
      expect(result.right.text, 'hello');
    });

    test('splits at end', () {
      final f = Fragment('hello');
      final result = FragmentOperations.splitFragment(f, 5);
      expect(result.left.text, 'hello');
      expect(result.right.text, '');
    });

    test('preserves styles on both parts', () {
      final f = Fragment('hello', styles: ['bold'], color: '#FF0000');
      final result = FragmentOperations.splitFragment(f, 2);
      expect(result.left.styles, contains('bold'));
      expect(result.left.color, '#FF0000');
      expect(result.right.styles, contains('bold'));
      expect(result.right.color, '#FF0000');
    });
  });

  group('mergeFragments', () {
    test('concatenates text', () {
      final a = Fragment('hello');
      final b = Fragment(' world');
      FragmentOperations.mergeFragments(a, b);
      expect(a.text, 'hello world');
    });

    test('does not modify second fragment', () {
      final a = Fragment('hello');
      final b = Fragment(' world');
      FragmentOperations.mergeFragments(a, b);
      expect(b.text, ' world');
    });
  });
}
