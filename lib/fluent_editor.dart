import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/plugins/builtin_plugin.dart';
import 'package:fluent_editor/plugins/plugin_api.dart';
import 'package:flutter/material.dart';

class FluentEditor extends StatefulWidget {
  final FluentDocument? document;
  final FluentEditorLabels? labels;
  final Widget? sidebar;
  final List<FluentEditorPlugin> plugins;
  final FluentToolbarMode toolbarMode;
  const FluentEditor({super.key, this.document, this.labels, this.sidebar, this.plugins = const [], this.toolbarMode = FluentToolbarMode.fixed});
  @override
  State<FluentEditor> createState() => _FluentEditorState();
}
class _FluentEditorState extends State<FluentEditor> {
  late FluentDocument _document;

  @override
  void initState() {
    super.initState();
    _document = widget.document ?? FluentDocument(
      registry: createDefaultFluentPluginRegistry(widget.plugins),
    );
    _document.labels = widget.labels;
    _document.addListener(_onDocumentChanged);
    _document.registry.attach(_document);
  }

  void _onDocumentChanged() {
    if (_document.cursorOnlyChange) return;
    setState(() {});
  }

  @override
  void dispose() {
    _document.registry.detach(_document);
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
          Expanded(
            child: FluentDocumentWidget(document: _document, labels: widget.labels, sidebar: widget.sidebar, toolbarMode: widget.toolbarMode),
          ),
        ],
      ),
    );
  }
}