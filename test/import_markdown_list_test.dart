import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/services/import_markdown_service.dart';

void main() {
  group('ImportMarkdownService list parsing', () {
    final service = ImportMarkdownService();

    test('parent ordered list with nested ordered list', () {
      final md = '''
1. Basic editing
2. Advanced formatting 
    1. Bold, italic, underline
    2. Superscript and subscript
    3. Colors and highlighting
3. Export and import
4. Text highlight
5. Text colors
6. Word and char count
'''.trim();

      final root = service.importFromMarkdown(md);

      // Find the list
      final lists = root.nodes.whereType<FluentList>().toList();
      expect(lists.length, 1, reason: 'Should have one top-level list');

      final parentList = lists.first;
      expect(parentList.listType, 'ordered',
          reason: 'Parent list should be ordered');
      expect(parentList.items.length, 6,
          reason: 'Parent list should have 6 items');

      for (int i = 0; i < parentList.items.length; i++) {
        final item = parentList.items[i];
        expect(item.bulletType, 'ordered',
            reason: 'Parent item ${i + 1} should have bulletType=ordered');
        expect(item.indexList, [i + 1],
            reason: 'Parent item ${i + 1} should have indexList=[${i + 1}]');
      }

      // Check sub-list in item 2 (index 1)
      final item2 = parentList.items[1];
      final subLists = item2.getChildren().whereType<FluentList>().toList();
      expect(subLists.length, 1, reason: 'Item 2 should have a sub-list');

      final subList = subLists.first;
      expect(subList.listType, 'ordered',
          reason: 'Sub-list should be ordered');
      expect(subList.items.length, 3,
          reason: 'Sub-list should have 3 items');

      for (int i = 0; i < subList.items.length; i++) {
        final item = subList.items[i];
        expect(item.bulletType, 'ordered',
            reason: 'Sub-item ${i + 1} should have bulletType=ordered');
        expect(item.indexList, [i + 1],
            reason: 'Sub-item ${i + 1} should have indexList=[${i + 1}]');
      }
    });

    test('bullet list followed by ordered list (separate lists)', () {
      final md = '''
- Bullet item 1
- Bullet item 2

1. Ordered item 1
2. Ordered item 2
'''.trim();

      final root = service.importFromMarkdown(md);

      // Find all lists
      final lists = root.nodes.whereType<FluentList>().toList();
      expect(lists.length, 2, reason: 'Should have two separate lists');

      // First list should be bullet
      final bulletList = lists[0];
      expect(bulletList.listType, 'bullet',
          reason: 'First list should be bullet');
      expect(bulletList.items.length, 2,
          reason: 'Bullet list should have 2 items');
      for (final item in bulletList.items) {
        expect(item.bulletType, 'bullet',
            reason: 'Bullet list items should have bulletType=bullet');
      }

      // Second list should be ordered
      final orderedList = lists[1];
      expect(orderedList.listType, 'ordered',
          reason: 'Second list should be ordered');
      expect(orderedList.items.length, 2,
          reason: 'Ordered list should have 2 items');
      for (int i = 0; i < orderedList.items.length; i++) {
        final item = orderedList.items[i];
        expect(item.bulletType, 'ordered',
            reason: 'Ordered list item ${i + 1} should have bulletType=ordered');
        expect(item.indexList, [i + 1],
            reason: 'Ordered list item ${i + 1} should have indexList=[${i + 1}]');
      }
    });

    test('heading styles are applied correctly', () {
      final md = '''
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
Normal paragraph
'''.trim();

      final root = service.importFromMarkdown(md);

      // Get all paragraphs
      final paragraphs = root.nodes.whereType<Paragraph>().toList();
      expect(paragraphs.length, 7, reason: 'Should have 6 headings + 1 normal paragraph');

      // Check heading styles
      expect(paragraphs[0].styleName, 'heading1', reason: 'First line should be heading1');
      expect(paragraphs[1].styleName, 'heading2', reason: 'Second line should be heading2');
      expect(paragraphs[2].styleName, 'heading3', reason: 'Third line should be heading3');
      expect(paragraphs[3].styleName, 'heading4', reason: 'Fourth line should be heading4');
      expect(paragraphs[4].styleName, 'heading5', reason: 'Fifth line should be heading5');
      expect(paragraphs[5].styleName, 'heading6', reason: 'Sixth line should be heading6');
      
      // Check normal paragraph has null or 'normal' style
      final normalStyle = paragraphs[6].styleName;
      expect(normalStyle == null || normalStyle == 'normal', true,
          reason: 'Normal paragraph should have null or "normal" style');
    });
  });
}
