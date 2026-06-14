import 'package:flutter/material.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'test_large_document.dart';

void main() {
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FluentEditor Virtualization Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const VirtualizationTestPage(),
    );
  }
}

class VirtualizationTestPage extends StatefulWidget {
  const VirtualizationTestPage({super.key});

  @override
  State<VirtualizationTestPage> createState() => _VirtualizationTestPageState();
}

class _VirtualizationTestPageState extends State<VirtualizationTestPage> {
  late FluentDocument _document;
  bool _useLargeDocument = false;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  void _loadDocument() {
    if (_useLargeDocument) {
      // Load a very large document to test virtualization
      _document = TestDocumentGenerator.generateLargeDocument(paragraphCount: 1000);
    } else {
      // Load a small document for normal testing
      _document = TestDocumentGenerator.generateMixedContentDocument(sections: 5);
    }
  }

  void _toggleDocumentSize() {
    setState(() {
      _useLargeDocument = !_useLargeDocument;
      _loadDocument();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_useLargeDocument ? 'Large Document Test' : 'Small Document Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _toggleDocumentSize,
            tooltip: 'Toggle document size',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Row(
              children: [
                Icon(
                  _useLargeDocument ? Icons.speed : Icons.document_scanner,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _useLargeDocument 
                        ? 'Testing virtualization with ${_document.content.nodes.length} nodes'
                        : 'Normal mode with ${_document.content.nodes.length} nodes',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: _toggleDocumentSize,
                  child: Text(_useLargeDocument ? 'Switch to Small' : 'Switch to Large'),
                ),
              ],
            ),
          ),
          Expanded(
            child: FluentEditor(
              document: _document,
            ),
          ),
        ],
      ),
    );
  }
}
