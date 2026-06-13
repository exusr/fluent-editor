import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';

void main() {
  group('flattenFragmentsSimple', () {
    test('flattens paragraph with single fragment', () {
      final p = Paragraph(text: 'hello');
      final flat = flattenFragmentsSimple(p);
      expect(flat.length, 1);
      expect(flat.first.$1.text, 'hello');
      expect(flat.first.$2, 0); // start
      expect(flat.first.$3, 5); // end
    });

    test('flattens paragraph with multiple fragments', () {
      final p = Paragraph();
      p.fragments = [Fragment('hello'), Fragment(' world')];
      final flat = flattenFragmentsSimple(p);
      expect(flat.length, 2);
      expect(flat[0].$1.text, 'hello');
      expect(flat[0].$2, 0);
      expect(flat[0].$3, 5);
      expect(flat[1].$1.text, ' world');
      expect(flat[1].$2, 5);
      expect(flat[1].$3, 11);
    });

    test('Link is transparent during flattening', () {
      final root = Root(nodes: [
        Paragraph()..fragments = [
          Fragment('visit '),
          Link(url: 'https://x.com', text: 'x'),
          Fragment('.com'),
        ],
      ]);
      final p = root.nodes.first as Paragraph;
      final flat = flattenFragmentsSimple(p);
      expect(flat.length, 3);
      expect(flat[0].$1.text, 'visit ');
      expect(flat[1].$1.text, 'x');
      expect(flat[2].$1.text, '.com');
    });

    test('FluentImage produces empty list in paragraph context', () {
      final p = Paragraph()..fragments = [FluentImage('https://img.png')];
      final flat = flattenFragmentsSimple(p);
      expect(flat, isEmpty);
    });

    test('Root flattens all children', () {
      final root = Root(nodes: [
        Paragraph(text: 'ab'),
        Paragraph(text: 'cd'),
      ]);
      final flat = flattenFragmentsSimple(root);
      expect(flat.length, 2);
      expect(flat[0].$1.text, 'ab');
      expect(flat[1].$1.text, 'cd');
    });
  });

  group('getFirstFragmentRecursive', () {
    test('finds first fragment in paragraph', () {
      final p = Paragraph(text: 'hello');
      final f = getFirstFragmentRecursive(p);
      expect(f, isNotNull);
      expect(f!.text, 'hello');
    });

    test('finds first fragment through Link', () {
      final p = Paragraph()..fragments = [Link(url: 'https://x.com', text: 'link')];
      final f = getFirstFragmentRecursive(p);
      expect(f, isNotNull);
      expect(f!.text, 'link');
    });

    test('skips empty fragments', () {
      final p = Paragraph();
      p.fragments = [Fragment(''), Fragment('hello')];
      final f = getFirstFragmentRecursive(p);
      expect(f, isNotNull);
      expect(f!.text, 'hello');
    });

    test('returns null for empty container', () {
      final p = Paragraph();
      p.fragments = [Fragment('')];
      final f = getFirstFragmentRecursive(p);
      expect(f, isNull);
    });
  });

  group('getLastFragmentRecursive', () {
    test('finds last fragment in paragraph', () {
      final p = Paragraph(text: 'hello');
      final f = getLastFragmentRecursive(p);
      expect(f, isNotNull);
      expect(f!.text, 'hello');
    });

    test('finds last fragment through Link', () {
      final p = Paragraph()..fragments = [Link(url: 'https://x.com', text: 'link')];
      final f = getLastFragmentRecursive(p);
      expect(f, isNotNull);
      expect(f!.text, 'link');
    });

    test('skips empty fragments', () {
      final p = Paragraph();
      p.fragments = [Fragment('hello'), Fragment('')];
      final f = getLastFragmentRecursive(p);
      expect(f, isNotNull);
      expect(f!.text, 'hello');
    });

    test('returns null for empty container', () {
      final p = Paragraph();
      p.fragments = [Fragment('')];
      final f = getLastFragmentRecursive(p);
      expect(f, isNull);
    });
  });
}
