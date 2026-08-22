import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/node_widget_builder.dart';
import 'package:flutter/material.dart';

/// Widget for table cells that support generic content.
/// Can contain paragraphs, images, nested tables, etc.
class FluentCellWidget extends StatefulWidget {
  const FluentCellWidget({
    super.key,
    required this.node,
    required this.document,
  });

  final FluentCell node;
  final FluentDocument document;

  @override
  State<FluentCellWidget> createState() => _FluentCellWidgetState();
}

class _FluentCellWidgetState extends State<FluentCellWidget> {
  bool _lastHadCursor = false;
  bool _lastHadSelection = false;

  @override
  void initState() {
    super.initState();
    widget.document.cursor.addListener(_onStateChange);
    widget.document.selectionManager.addListener(_onStateChange);
  }

  @override
  void didUpdateWidget(FluentCellWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.cursor != widget.document.cursor) {
      oldWidget.document.cursor.removeListener(_onStateChange);
      widget.document.cursor.addListener(_onStateChange);
    }
    if (oldWidget.document.selectionManager != widget.document.selectionManager) {
      oldWidget.document.selectionManager.removeListener(_onStateChange);
      widget.document.selectionManager.addListener(_onStateChange);
    }
  }

  @override
  void dispose() {
    widget.document.cursor.removeListener(_onStateChange);
    widget.document.selectionManager.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    final nodeId = widget.node.id;
    final doc = widget.document;
    final hasCursor = doc.cachedCursorContainerId == nodeId;
    final hasSelection = doc.isNodeSelected(nodeId);
    if (hasCursor == _lastHadCursor && hasSelection == _lastHadSelection) return;
    _lastHadCursor = hasCursor;
    _lastHadSelection = hasSelection;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final liveCell = (findById(widget.document.content, widget.node.id) as FluentCell?) ?? widget.node;
    final childrenWidgets = <Widget>[];

    for (final child in liveCell.children) {
      childrenWidgets.add(buildFNodeWidget(child, widget.document));
    }

    if (childrenWidgets.isEmpty) {
      final emptyParagraph = Paragraph();
      childrenWidgets.add(buildFNodeWidget(emptyParagraph, widget.document));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: childrenWidgets,
      ),
    );
  }
}
