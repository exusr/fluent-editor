import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/services/docx_exporter.dart';
import 'package:fluent_editor/suggestions/suggestion_provider.dart';

class MockSuggestionProvider extends SuggestionProvider {
  final List<Map<String, dynamic>> _suggestions;
  MockSuggestionProvider(this._suggestions);

  @override
  Stream<void> get suggestionsChanged => const Stream.empty();

  @override
  List<Map<String, dynamic>> exportSuggestions() => _suggestions;

  @override
  List<Map<String, dynamic>> suggestionsForNode(String nodeId) {
    return _suggestions.where((s) => s['nodeId'] == nodeId).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DocxExporter Tracked Changes Tests', () {
    test('Exports additions and deletions with suggestionProvider to <w:ins> and <w:del>', () async {
      final p = Paragraph();
      final fragNormal = Fragment('Hello ');
      final fragAdded = Fragment('added ', styles: ['suggestion_addition']);
      final fragDeleted = Fragment('deleted', styles: ['suggestion_deletion', 'strikethrough']);

      p.fragments.addAll([fragNormal, fragAdded, fragDeleted]);
      final doc = FluentDocument(content: Root()..nodes.add(p));

      final provider = MockSuggestionProvider([
        {
          'id': 's1',
          'nodeId': p.id,
          'type': 'addition',
          'authorName': 'Alice',
          'createdAt': '2026-08-03T10:00:00Z',
        },
        {
          'id': 's2',
          'nodeId': p.id,
          'type': 'deletion',
          'authorName': 'Bob',
          'createdAt': '2026-08-03T11:00:00Z',
        },
      ]);
      doc.suggestionProvider = provider;

      final exporter = DocxExporter(doc);
      final bytes = await exporter.build();
      expect(bytes.isNotEmpty, isTrue);

      final archive = ZipDecoder().decodeBytes(bytes);
      final docXmlFile = archive.findFile('word/document.xml');
      expect(docXmlFile, isNotNull);

      final xmlStr = utf8.decode(docXmlFile!.content as List<int>);

      // Verify <w:ins> with Alice as author
      expect(xmlStr.contains('<w:ins'), isTrue);
      expect(xmlStr.contains('w:author="Alice"'), isTrue);
      expect(xmlStr.contains('added '), isTrue);

      // Verify <w:del> with Bob as author and <w:delText>
      expect(xmlStr.contains('<w:del'), isTrue);
      expect(xmlStr.contains('w:author="Bob"'), isTrue);
      expect(xmlStr.contains('<w:delText xml:space="preserve">deleted</w:delText>'), isTrue);
    });

    test('Exports additions and deletions WITHOUT suggestionProvider (fallback mode) to <w:ins> and <w:del>', () async {
      final p = Paragraph();
      final fragAdded = Fragment('new text', styles: ['suggestion_addition']);
      final fragDeleted = Fragment('old text', styles: ['suggestion_deletion', 'strikethrough']);

      p.fragments.addAll([fragAdded, fragDeleted]);
      final doc = FluentDocument(content: Root()..nodes.add(p));
      expect(doc.suggestionProvider, isNull);

      final exporter = DocxExporter(doc);
      final bytes = await exporter.build();
      expect(bytes.isNotEmpty, isTrue);

      final archive = ZipDecoder().decodeBytes(bytes);
      final docXmlFile = archive.findFile('word/document.xml');
      expect(docXmlFile, isNotNull);

      final xmlStr = utf8.decode(docXmlFile!.content as List<int>);

      // Verify <w:ins> and <w:del> exist even without provider
      expect(xmlStr.contains('<w:ins'), isTrue);
      expect(xmlStr.contains('new text'), isTrue);

      expect(xmlStr.contains('<w:del'), isTrue);
      expect(xmlStr.contains('<w:delText xml:space="preserve">old text</w:delText>'), isTrue);
    });
  });
}
