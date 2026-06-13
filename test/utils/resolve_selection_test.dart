import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';

void main() {
  group('resolveSelection', () {
    late Root root;
    late String fragId;

    setUp(() {
      root = Root(nodes: [
        Paragraph(text: 'hello world'),
        Paragraph(text: 'second paragraph'),
      ]);
      fragId = ((root.nodes.first as Paragraph).fragments.first as Fragment).id;
    });

    test('returns null for collapsed selection', () {
      final sel = resolveSelection(root, fragId, 2, fragId, 2);
      expect(sel, isNull);
    });

    test('resolves single-fragment selection', () {
      final sel = resolveSelection(root, fragId, 0, fragId, 5);
      expect(sel, isNotNull);
      expect(sel!.nodes.length, 1);
      expect(sel.isSingleNode, isTrue);
      expect(sel.isMultiNode, isFalse);
      expect(sel.nodes.first.startOffset, 0);
      expect(sel.nodes.first.endOffset, 5);
      expect(sel.nodes.first.isFullySelected, isFalse);
    });

    test('resolves multi-paragraph selection', () {
      final frag2 = ((root.nodes.last as Paragraph).fragments.first as Fragment).id;
      final sel = resolveSelection(root, fragId, 6, frag2, 6);
      expect(sel, isNotNull);
      expect(sel!.nodes.length, 2);
      expect(sel.isMultiNode, isTrue);
      expect(sel.nodes.first.isFullySelected, isFalse);
      expect(sel.nodes.last.isFullySelected, isFalse);
    });

    test('fully selects intermediate nodes', () {
      final root3 = Root(nodes: [
        Paragraph(text: 'a'),
        Paragraph(text: 'b'),
        Paragraph(text: 'c'),
      ]);
      final f1 = ((root3.nodes[0] as Paragraph).fragments.first as Fragment).id;
      final f3 = ((root3.nodes[2] as Paragraph).fragments.first as Fragment).id;
      final sel = resolveSelection(root3, f1, 1, f3, 0);
      expect(sel, isNotNull);
      expect(sel!.nodes.length, 3);
      expect(sel.nodes[0].isFullySelected, isFalse);
      expect(sel.nodes[1].isFullySelected, isTrue);
      expect(sel.nodes[2].isFullySelected, isFalse);
    });

    test('returns null for unknown fragment id', () {
      final sel = resolveSelection(root, 'unknown', 0, fragId, 5);
      expect(sel, isNull);
    });

    test('base and extent are ordered correctly', () {
      final frag2 = ((root.nodes.last as Paragraph).fragments.first as Fragment).id;
      // anchor after focus → base should be focus
      final sel = resolveSelection(root, frag2, 6, fragId, 0);
      expect(sel, isNotNull);
      expect(sel!.base.fragment.id, fragId);
      expect(sel.base.offset, 0);
      expect(sel.extent.fragment.id, frag2);
      expect(sel.extent.offset, 6);
    });
  });

  group('SelectionEndpoint', () {
    test('toString includes fragment id and offset', () {
      final frag = Fragment('hello');
      final p = Paragraph();
      p.fragments = [frag];
      final ep = SelectionEndpoint(fragment: frag, offset: 2, container: p);
      expect(ep.toString(), contains(frag.id));
      expect(ep.toString(), contains('2'));
    });
  });

  group('SelectedNode', () {
    test('toString includes range and full flag', () {
      final frag = Fragment('hello');
      final p = Paragraph();
      p.fragments = [frag];
      final sn = SelectedNode(
        container: p,
        startFragment: frag,
        startOffset: 1,
        endFragment: frag,
        endOffset: 4,
        isFullySelected: false,
      );
      expect(sn.toString(), contains('1'));
      expect(sn.toString(), contains('4'));
      expect(sn.toString(), contains('full=false'));
    });
  });

  group('ResolvedSelection', () {
    test('isSingleNode and isMultiNode', () {
      final frag = Fragment('hello');
      final p = Paragraph();
      p.fragments = [frag];
      final ep = SelectionEndpoint(fragment: frag, offset: 0, container: p);
      final sel = ResolvedSelection(
        anchor: ep,
        focus: ep,
        base: ep,
        extent: ep,
        nodes: [
          SelectedNode(
            container: p,
            startFragment: frag,
            startOffset: 0,
            endFragment: frag,
            endOffset: 5,
            isFullySelected: true,
          ),
        ],
      );
      expect(sel.isSingleNode, isTrue);
      expect(sel.isMultiNode, isFalse);
    });
  });
}
