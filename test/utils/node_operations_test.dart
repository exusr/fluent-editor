import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/node_operations.dart';

void main() {
  group('childrenOf', () {
    test('returns Root.nodes', () {
      final root = Root(nodes: [Paragraph(text: 'a')]);
      expect(childrenOf(root).length, 1);
      expect(childrenOf(root).first, root.nodes.first);
    });

    test('returns Paragraph.fragments', () {
      final p = Paragraph(text: 'hello');
      expect(childrenOf(p).length, 1);
    });

    test('returns FluentList.items (including default item)', () {
      final list = FluentList(listType: 'bullet');
      list.items.add(ListItem(bulletType: 'bullet', indexList: [1]));
      expect(childrenOf(list).length, 1);
    });

    test('returns FluentTable.rows', () {
      final table = FluentTable(rows: [FluentRow()]);
      expect(childrenOf(table).length, 1);
    });

    test('returns FluentRow.cells', () {
      final row = FluentRow(cells: [FluentCell()]);
      expect(childrenOf(row).length, 1);
    });

    test('returns empty for Fragment', () {
      final f = Fragment('hello');
      expect(childrenOf(f), isEmpty);
    });

    test('returns Link fragments', () {
      final link = Link(url: 'https://x.com', text: 'hello');
      expect(childrenOf(link).length, 1);
    });
  });

  group('findNode / findById', () {
    late Root root;

    setUp(() {
      root = Root(nodes: [
        Paragraph(text: 'hello'),
        FluentTable(rows: [
          FluentRow(cells: [
            FluentCell(children: [Paragraph(text: 'cell')]),
          ]),
        ]),
      ]);
    });

    test('finds top-level node', () {
      final p = root.nodes.first as Paragraph;
      final found = findById(root, p.fragments.first.id);
      expect(found, isNotNull);
      expect(found!.id, p.fragments.first.id);
    });

    test('finds nested cell paragraph', () {
      final table = root.nodes[1] as FluentTable;
      final cell = table.rows.first.cells.first;
      final p = cell.children.first as Paragraph;
      final found = findById(root, p.fragments.first.id);
      expect(found, isNotNull);
      expect(found!.id, p.fragments.first.id);
    });

    test('returns null for unknown id', () {
      final found = findById(root, 'unknown-id');
      expect(found, isNull);
    });

    test('findNode with custom predicate', () {
      final found = findNode(root, (n) => n is FluentCell);
      expect(found, isNotNull);
      expect(found is FluentCell, isTrue);
    });
  });

  group('findParent', () {
    test('finds direct parent', () {
      final root = Root(nodes: [Paragraph(text: 'hello')]);
      final p = root.nodes.first as Paragraph;
      final f = p.fragments.first;
      final parent = findParent(root, f);
      expect(parent, p);
    });

    test('returns null for root', () {
      final root = Root();
      final parent = findParent(root, root);
      expect(parent, isNull);
    });

    test('finds parent in nested structure', () {
      final cell = FluentCell(children: [Paragraph(text: 'hello')]);
      final p = cell.children.first as Paragraph;
      final parent = findParent(cell, p);
      expect(parent, cell);
    });
  });

  group('findLogicalContainer', () {
    test('finds container for Fragment in Paragraph', () {
      final root = Root(nodes: [Paragraph(text: 'hello')]);
      final p = root.nodes.first as Paragraph;
      final f = p.fragments.first as Fragment;
      final container = findLogicalContainer(root, f.id);
      expect(container, p);
    });

    test('Link is transparent', () {
      final root = Root(nodes: [
        Paragraph()
          ..fragments = [Link(url: 'https://x.com', text: 'hello')],
      ]);
      final link = (root.nodes.first as Paragraph).fragments.first as Link;
      final f = link.fragments.first as Fragment;
      final container = findLogicalContainer(root, f.id);
      expect(container, root.nodes.first);
    });

    test('FluentImage in Paragraph returns Paragraph', () {
      final root = Root(nodes: [
        Paragraph()..fragments = [FluentImage('https://img.png')],
      ]);
      final img = (root.nodes.first as Paragraph).fragments.first as FluentImage;
      final container = findLogicalContainer(root, img.id);
      expect(container, root.nodes.first);
    });

    test('block-level FluentImage returns itself', () {
      final root = Root(nodes: [FluentImage('https://img.png')]);
      final img = root.nodes.first as FluentImage;
      final container = findLogicalContainer(root, img.id);
      expect(container, img);
    });

    test('HorizontalRule returns itself', () {
      final root = Root(nodes: [HorizontalRule()]);
      final hr = root.nodes.first as HorizontalRule;
      final container = findLogicalContainer(root, hr.id);
      expect(container, hr);
    });
  });

  group('pathTo', () {
    test('returns path to nested node', () {
      final root = Root(nodes: [
        FluentTable(rows: [
          FluentRow(cells: [FluentCell()]),
        ]),
      ]);
      final cell = (root.nodes.first as FluentTable).rows.first.cells.first;
      final path = pathTo(root, cell);
      expect(path, isNotNull);
      expect(path!.length, 4); // Root -> Table -> Row -> Cell
      expect(path[0], root);
      expect(path[1] is FluentTable, isTrue);
      expect(path[2] is FluentRow, isTrue);
      expect(path[3] is FluentCell, isTrue);
    });

    test('returns null for unknown node', () {
      final root = Root();
      final path = pathTo(root, Paragraph(text: 'orphan'));
      expect(path, isNull);
    });
  });

  group('walkTree', () {
    test('visits all nodes', () {
      final root = Root(nodes: [Paragraph(text: 'hello')]);
      final visited = <String>[];
      walkTree(root, (node, _) {
        visited.add(node.runtimeType.toString());
        return true;
      });
      expect(visited, containsAll(['Root', 'Paragraph', 'Fragment']));
    });

    test('stops early when visitor returns false', () {
      final root = Root(nodes: [
        Paragraph(text: 'a'),
        Paragraph(text: 'b'),
      ]);
      var count = 0;
      walkTree(root, (node, _) {
        count++;
        return false;
      });
      expect(count, 1); // only Root visited
    });
  });

  group('collectAllFragments', () {
    test('collects leaf fragments in order', () {
      final root = Root(nodes: [
        Paragraph(text: 'a'),
        Link(url: 'https://x.com', text: 'b'),
      ]);
      final fragments = collectAllFragments(root);
      expect(fragments.length, 2);
      expect(fragments[0].text, 'a');
      expect(fragments[1].text, 'b');
    });

    test('skips InlineContainerNode nodes', () {
      final root = Root(nodes: [
        FluentTable(rows: [
          FluentRow(cells: [
            FluentCell(children: [Paragraph(text: 'cell')]),
          ]),
        ]),
      ]);
      final fragments = collectAllFragments(root);
      expect(fragments.length, 1);
      expect(fragments.first.text, 'cell');
    });
  });

  group('CRUD operations', () {
    test('insertAfter adds node after sibling', () {
      final root = Root(nodes: [
        Paragraph(text: 'first'),
        Paragraph(text: 'second'),
      ]);
      final first = root.nodes.first;
      final newNode = Paragraph(text: 'middle');
      final ok = insertAfter(root, first, newNode);
      expect(ok, isTrue);
      expect(root.nodes.length, 3);
      expect((root.nodes[1] as Paragraph).text, 'middle');
    });

    test('insertAfter returns false for non-child', () {
      final root = Root();
      final ok = insertAfter(root, Paragraph(text: 'orphan'), Paragraph());
      expect(ok, isFalse);
    });

    test('insertBefore adds node before sibling', () {
      final root = Root(nodes: [
        Paragraph(text: 'first'),
        Paragraph(text: 'second'),
      ]);
      final second = root.nodes.last;
      final newNode = Paragraph(text: 'middle');
      final ok = insertBefore(root, second, newNode);
      expect(ok, isTrue);
      expect((root.nodes[1] as Paragraph).text, 'middle');
    });

    test('appendChild adds to end', () {
      final root = Root(nodes: [Paragraph(text: 'first')]);
      final ok = appendChild(root, Paragraph(text: 'last'));
      expect(ok, isTrue);
      expect(root.nodes.length, 2);
      expect((root.nodes.last as Paragraph).text, 'last');
    });

    test('prependChild adds to beginning', () {
      final root = Root(nodes: [Paragraph(text: 'last')]);
      final ok = prependChild(root, Paragraph(text: 'first'));
      expect(ok, isTrue);
      expect(root.nodes.length, 2);
      expect((root.nodes.first as Paragraph).text, 'first');
    });

    test('removeNode removes target', () {
      final root = Root(nodes: [
        Paragraph(text: 'a'),
        Paragraph(text: 'b'),
      ]);
      final target = root.nodes.last;
      final ok = removeNode(root, target);
      expect(ok, isTrue);
      expect(root.nodes.length, 1);
    });

    test('removeNode returns false for root', () {
      final root = Root();
      final ok = removeNode(root, root);
      expect(ok, isFalse);
    });

    test('replaceNode swaps nodes', () {
      final root = Root(nodes: [Paragraph(text: 'old')]);
      final old = root.nodes.first;
      final replacement = Paragraph(text: 'new');
      final ok = replaceNode(root, old, replacement);
      expect(ok, isTrue);
      expect((root.nodes.first as Paragraph).text, 'new');
    });
  });

  group('pruneEmptyContainers', () {
    test('removes empty container without children', () {
      final root = Root();
      final emptyList = FluentList(listType: 'bullet');
      root.nodes.add(emptyList);
      pruneEmptyContainers(emptyList, root);
      expect(root.nodes.whereType<FluentList>(), isEmpty);
    });

    test('does not remove container with children', () {
      final root = Root(nodes: [
        Paragraph(text: 'keep'),
      ]);
      final p = root.nodes.first as Paragraph;
      pruneEmptyContainers(p, root);
      expect(root.nodes.length, 1);
    });
  });

  group('recalculateListIndices', () {
    test('updates flat list indices', () {
      final list = FluentList(listType: 'numbered');
      list.items.add(ListItem(bulletType: 'numbered', indexList: []));
      list.items.add(ListItem(bulletType: 'numbered', indexList: []));
      final root = Root(nodes: [list]);
      recalculateListIndices(root);
      expect(list.items[0].indexList, [1]);
      expect(list.items[1].indexList, [2]);
    });

    test('updates nested list indices', () {
      final sublist = FluentList(listType: 'numbered');
      sublist.items.add(ListItem(bulletType: 'numbered', indexList: []));
      final item = ListItem(
        bulletType: 'numbered',
        indexList: [],
        children: [Paragraph(), sublist],
      );
      final list = FluentList(listType: 'numbered');
      list.items.add(item);
      final root = Root(nodes: [list]);
      recalculateListIndices(root);
      expect(item.indexList, [1]);
      expect(sublist.items.first.indexList, [1, 1]);
    });
  });

  group('mergeConsecutiveLists', () {
    test('merges two adjacent bullet lists with items', () {
      final list1 = FluentList(listType: 'bullet');
      list1.items.add(ListItem(bulletType: 'bullet', indexList: [1]));
      final list2 = FluentList(listType: 'bullet');
      list2.items.add(ListItem(bulletType: 'bullet', indexList: [1]));
      final root = Root(nodes: [list1, list2]);
      mergeConsecutiveLists(root);
      expect(root.nodes.length, 1);
      expect((root.nodes.first as FluentList).items.length, 2);
    });

    test('does not merge different types', () {
      final list1 = FluentList(listType: 'bullet');
      list1.items.add(ListItem(bulletType: 'bullet', indexList: [1]));
      final list2 = FluentList(listType: 'numbered');
      list2.items.add(ListItem(bulletType: 'numbered', indexList: [1]));
      final root = Root(nodes: [list1, list2]);
      mergeConsecutiveLists(root);
      expect(root.nodes.length, 2);
    });

    test('does not merge lists separated by other nodes', () {
      final list1 = FluentList(listType: 'bullet');
      list1.items.add(ListItem(bulletType: 'bullet', indexList: [1]));
      final list2 = FluentList(listType: 'bullet');
      list2.items.add(ListItem(bulletType: 'bullet', indexList: [1]));
      final root = Root(nodes: [list1, Paragraph(), list2]);
      mergeConsecutiveLists(root);
      expect(root.nodes.length, 3);
    });
  });

  group('outdentListItemToParagraph', () {
    test('transforms single list item to paragraph', () {
      final item = ListItem(
        bulletType: 'bullet',
        indexList: [1],
        children: [Paragraph(text: 'hello')],
      );
      final list = FluentList(listType: 'bullet')..items.add(item);
      final root = Root(nodes: [list]);
      final result = outdentListItemToParagraph(root, list, item);
      expect(result, isNotNull);
      expect(result!.text, 'hello');
      expect(root.nodes.length, 1);
      expect(root.nodes.first is Paragraph, isTrue);
    });

    test('preserves following items in new list', () {
      final item1 = ListItem(
        bulletType: 'bullet',
        indexList: [1],
        children: [Paragraph(text: 'first')],
      );
      final item2 = ListItem(
        bulletType: 'bullet',
        indexList: [2],
        children: [Paragraph(text: 'second')],
      );
      final list = FluentList(listType: 'bullet');
      list.items.addAll([item1, item2]);
      final root = Root(nodes: [list]);
      outdentListItemToParagraph(root, list, item1);
      expect(root.nodes.length, 2);
      expect(root.nodes[0] is Paragraph, isTrue);
      expect(root.nodes[1] is FluentList, isTrue);
    });
  });
}
