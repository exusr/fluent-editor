import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/services/export_service.dart';

void main() {
  group('ExportService Markdown export', () {
    test('headings are exported correctly', () {
      // Create document with headings
      final root = Root(nodes: [
        Paragraph(text: 'Heading 1', styleName: 'heading1'),
        Paragraph(text: 'Heading 2', styleName: 'heading2'),
        Paragraph(text: 'Heading 3', styleName: 'heading3'),
        Paragraph(text: 'Heading 4', styleName: 'heading4'),
        Paragraph(text: 'Heading 5', styleName: 'heading5'),
        Paragraph(text: 'Heading 6', styleName: 'heading6'),
        Paragraph(text: 'Normal paragraph'),
      ]);

      final doc = FluentDocument(content: root);
      final exportService = ExportService(doc);
      final md = exportService.exportToMarkdown();

      print('Exported Markdown:\n$md');

      // Check headings are exported with correct level
      expect(md.contains('# Heading 1'), true, reason: 'h1 should be exported');
      expect(md.contains('## Heading 2'), true, reason: 'h2 should be exported');
      expect(md.contains('### Heading 3'), true, reason: 'h3 should be exported');
      expect(md.contains('#### Heading 4'), true, reason: 'h4 should be exported');
      expect(md.contains('##### Heading 5'), true, reason: 'h5 should be exported');
      expect(md.contains('###### Heading 6'), true, reason: 'h6 should be exported');
    });
  });
}
