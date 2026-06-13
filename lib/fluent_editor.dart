import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:flutter/material.dart';

class FluentEditor extends StatefulWidget {
  final FluentDocument? document;
  final FluentEditorLabels? labels;
  final Widget? sidebar;
  const FluentEditor({super.key, this.document, this.labels, this.sidebar});
  @override
  State<FluentEditor> createState() => _FluentEditorState();
}
class _FluentEditorState extends State<FluentEditor> {
  // Document instance
  late FluentDocument _document;

  @override
  void initState() {
    super.initState();
    // If the user passes a document, use that one, otherwise create a new one
    _document = widget.document ?? FluentDocument();
    _document.labels = widget.labels;
    _document.addListener(_onDocumentChanged);
  }

  void _onDocumentChanged() {
    // Force widget rebuild when document content changes
    setState(() {});
  }

  @override
  void dispose() {
    _document.removeListener(_onDocumentChanged);
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.inverseSurface,
      body: Column(
        children: [
          // Example of an input area that updates the document
          Expanded(
            child: FluentDocumentWidget(document: _document, labels: widget.labels, sidebar: widget.sidebar),
          ),
        ],
      ),
    );
  }
}