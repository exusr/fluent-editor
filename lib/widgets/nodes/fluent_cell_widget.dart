import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
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

  void _onStateChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // Build widgets for all children of the cell
    final childrenWidgets = <Widget>[];

    for (final child in widget.node.children) {
      childrenWidgets.add(buildFNodeWidget(child, widget.document));
    }

    // If empty, show at least an empty paragraph for the cursor
    if (childrenWidgets.isEmpty) {
      final emptyParagraph = Paragraph();
      childrenWidgets.add(buildFNodeWidget(emptyParagraph, widget.document));
    }

    // Vertical layout for children
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
