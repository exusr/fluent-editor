import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';

void main() {
  group('CaretStop', () {
    test('equality works by value', () {
      const a = CaretStop('id1', 3);
      const b = CaretStop('id1', 3);
      const c = CaretStop('id1', 4);
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });

    test('hashCode is consistent', () {
      const a = CaretStop('id1', 3);
      const b = CaretStop('id1', 3);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('buildAllStops', () {
    test('paragraph with single fragment', () {
      final root = Root(nodes: [Paragraph(text: 'abc')]);
      final stops = buildAllStops(root);
      final fragId = ((root.nodes.first as Paragraph).fragments.first as Fragment).id;
      expect(stops.length, 4); // offsets 0,1,2,3
      expect(stops[0], CaretStop(fragId, 0));
      expect(stops[3], CaretStop(fragId, 3));
    });

    test('paragraph with multiple fragments shares boundary stop', () {
      // When two fragments are adjacent, the stop at the end of the first
      // and the start of the second represent the same logical position,
      // so only one is generated.
      final p = Paragraph();
      p.fragments = [Fragment('ab'), Fragment('cd')];
      final root = Root(nodes: [p]);
      final stops = buildAllStops(root);
      final f1 = (p.fragments[0] as Fragment).id;
      final f2 = (p.fragments[1] as Fragment).id;
      // Stops: f1:0, f1:1, [shared boundary f1:2/f2:0], f2:1, f2:2
      // The boundary is emitted as f2:0 (the next fragment)
      expect(stops.length, 5);
      expect(stops[0], CaretStop(f1, 0));
      expect(stops[1], CaretStop(f1, 1));
      expect(stops[2], CaretStop(f2, 0)); // shared boundary
      expect(stops[3], CaretStop(f2, 1));
      expect(stops[4], CaretStop(f2, 2));
    });

    test('HorizontalRule has 2 stops', () {
      final root = Root(nodes: [HorizontalRule()]);
      final stops = buildAllStops(root);
      final hr = root.nodes.first as HorizontalRule;
      expect(stops.length, 2);
      expect(stops[0], CaretStop(hr.id, 0));
      expect(stops[1], CaretStop(hr.id, 1));
    });

    test('FluentImage has 2 stops', () {
      final root = Root(nodes: [FluentImage('https://img.png')]);
      final stops = buildAllStops(root);
      final img = root.nodes.first as FluentImage;
      expect(stops.length, 2);
      expect(stops[0], CaretStop(img.id, 0));
      expect(stops[1], CaretStop(img.id, 1));
    });

    test('Link is transparent', () {
      final root = Root(nodes: [
        Paragraph()..fragments = [Link(url: 'https://x.com', text: 'ab')],
      ]);
      final stops = buildAllStops(root);
      final link = ((root.nodes.first as Paragraph).fragments.first as Link);
      final frag = link.fragments.first as Fragment;
      expect(stops.length, 3);
      expect(stops[0].fragmentId, frag.id);
    });

    test('FluentTable cells produce stops', () {
      final root = Root(nodes: [
        FluentTable(rows: [
          FluentRow(cells: [
            FluentCell(children: [Paragraph(text: 'ab')]),
          ]),
        ]),
      ]);
      final stops = buildAllStops(root);
      expect(stops.length, 3); // cell paragraph: 0,1,2
    });

    test('FluentList items produce stops', () {
      final root = Root(nodes: [
        FluentList(listType: 'bullet')
          ..items.add(ListItem(bulletType: 'bullet', indexList: [1], children: [Paragraph(text: 'ab')])),
      ]);
      final stops = buildAllStops(root);
      expect(stops.length, 3);
    });

    test('empty document has no stops', () {
      final root = Root(nodes: []);
      final stops = buildAllStops(root);
      expect(stops, isEmpty);
    });
  });

  group('buildAllLogicalLines', () {
    test('each paragraph is a line', () {
      final root = Root(nodes: [
        Paragraph(text: 'a'),
        Paragraph(text: 'b'),
      ]);
      final lines = buildAllLogicalLines(root);
      expect(lines.length, 2);
    });

    test('table cells are separate lines', () {
      final root = Root(nodes: [
        FluentTable(rows: [
          FluentRow(cells: [
            FluentCell(children: [Paragraph(text: 'a')]),
            FluentCell(children: [Paragraph(text: 'b')]),
          ]),
        ]),
      ]);
      final lines = buildAllLogicalLines(root);
      expect(lines.length, 2);
    });

    test('HorizontalRule is a line', () {
      final root = Root(nodes: [HorizontalRule()]);
      final lines = buildAllLogicalLines(root);
      expect(lines.length, 1);
      expect(lines.first.stops.length, 2);
    });
  });

  group('findStopIndex', () {
    test('finds exact match', () {
      final stops = [const CaretStop('a', 0), const CaretStop('a', 1), const CaretStop('b', 0)];
      expect(findStopIndex(stops, 'a', 0), 0);
      expect(findStopIndex(stops, 'a', 1), 1);
      expect(findStopIndex(stops, 'b', 0), 2);
    });

    test('returns -1 for unknown id', () {
      final stops = [const CaretStop('a', 0)];
      expect(findStopIndex(stops, 'unknown', 0), -1);
    });

    test('finds closest offset for same fragment', () {
      final stops = [const CaretStop('a', 0), const CaretStop('a', 5)];
      expect(findStopIndex(stops, 'a', 3), 1); // closest to 5
    });
  });

  group('findLineForStop', () {
    test('finds line containing stop', () {
      final root = Root(nodes: [
        Paragraph(text: 'a'),
        Paragraph(text: 'b'),
      ]);
      final lines = buildAllLogicalLines(root);
      final stop = lines[1].stops.first;
      final result = findLineForStop(lines, stop);
      expect(result, isNotNull);
      expect(result!.lineIndex, 1);
    });

    test('returns null for unknown stop', () {
      final root = Root(nodes: [Paragraph(text: 'a')]);
      final lines = buildAllLogicalLines(root);
      final result = findLineForStop(lines, const CaretStop('unknown', 0));
      expect(result, isNull);
    });
  });

  group('moveLeft', () {
    test('moves to previous stop', () {
      final root = Root(nodes: [Paragraph(text: 'ab')]);
      final stops = buildAllStops(root);
      final result = moveLeft(root, stops[1]);
      expect(result.position, stops[0]);
    });

    test('returns none at first stop', () {
      final root = Root(nodes: [Paragraph(text: 'ab')]);
      final stops = buildAllStops(root);
      final result = moveLeft(root, stops[0]);
      expect(result.position, isNull);
    });
  });

  group('moveRight', () {
    test('moves to next stop', () {
      final root = Root(nodes: [Paragraph(text: 'ab')]);
      final stops = buildAllStops(root);
      final result = moveRight(root, stops[0]);
      expect(result.position, stops[1]);
    });

    test('returns none at last stop', () {
      final root = Root(nodes: [Paragraph(text: 'ab')]);
      final stops = buildAllStops(root);
      final result = moveRight(root, stops.last);
      expect(result.position, isNull);
    });
  });

  group('NavigationResult', () {
    test('none has null position', () {
      expect(NavigationResult.none.position, isNull);
      expect(NavigationResult.none.preferredX, 0.0);
    });
  });
}
