import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/services/odt_exporter.dart';
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

  group('OdtExporter Tracked Changes Tests', () {
    test('Exports additions and deletions with suggestionProvider to ODT tracked changes', () async {
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

      final exporter = OdtExporter(doc);
      final bytes = await exporter.build();
      expect(bytes.isNotEmpty, isTrue);

      final archive = ZipDecoder().decodeBytes(bytes);
      final contentXmlFile = archive.findFile('content.xml');
      expect(contentXmlFile, isNotNull);

      final xmlStr = utf8.decode(contentXmlFile!.content as List<int>);

      // Verify <text:tracked-changes> header and regions
      expect(xmlStr.contains('<text:tracked-changes text:track-changes="true">'), isTrue);
      expect(xmlStr.contains('<text:changed-region'), isTrue);
      expect(xmlStr.contains('<dc:creator>Alice</dc:creator>'), isTrue);
      expect(xmlStr.contains('<dc:creator>Bob</dc:creator>'), isTrue);

      // Verify inline <text:change-start> and <text:change-end>
      expect(xmlStr.contains('<text:change-start'), isTrue);
      expect(xmlStr.contains('<text:change-end'), isTrue);
    });

    test('Exports additions and deletions WITHOUT suggestionProvider (fallback mode) to ODT tracked changes', () async {
      final p = Paragraph();
      final fragAdded = Fragment('new text', styles: ['suggestion_addition']);
      final fragDeleted = Fragment('old text', styles: ['suggestion_deletion', 'strikethrough']);

      p.fragments.addAll([fragAdded, fragDeleted]);
      final doc = FluentDocument(content: Root()..nodes.add(p));
      expect(doc.suggestionProvider, isNull);

      final exporter = OdtExporter(doc);
      final bytes = await exporter.build();
      expect(bytes.isNotEmpty, isTrue);

      final archive = ZipDecoder().decodeBytes(bytes);
      final contentXmlFile = archive.findFile('content.xml');
      expect(contentXmlFile, isNotNull);

      final xmlStr = utf8.decode(contentXmlFile!.content as List<int>);

      // Verify <text:tracked-changes> header and regions exist without provider
      expect(xmlStr.contains('<text:tracked-changes text:track-changes="true">'), isTrue);
      expect(xmlStr.contains('<text:changed-region'), isTrue);
      expect(xmlStr.contains('<text:change-start'), isTrue);
      expect(xmlStr.contains('<text:change-end'), isTrue);
    });
  });
}
