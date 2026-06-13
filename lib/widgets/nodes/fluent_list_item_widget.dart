import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/editor_utils.dart';
import 'package:fluent_editor/widgets/nodes/fluent_paragraph_widget.dart';
import 'package:fluent_editor/widgets/dialogs/list_marker_dialog.dart';
import 'package:flutter/material.dart';

/// ListItem widget with support for generic children (Paragraph, Image, Table)
class FluentListItemWidget extends StatefulWidget {
  static const double _markerWidth = 35.0;

  const FluentListItemWidget({
    super.key,
    required this.node,
    required this.document,
  });

  final ListItem node;
  final FluentDocument document;

  @override
  State<FluentListItemWidget> createState() => _FluentListItemWidgetState();
}

class _FluentListItemWidgetState extends State<FluentListItemWidget> {
  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onStateChange);
  }

  @override
  void didUpdateWidget(FluentListItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onStateChange);
      widget.document.addListener(_onStateChange);
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final allChildren = widget.node.getChildren();

    // Separate children: first Paragraph for the marker, rest as block
    final firstParagraph = allChildren.whereType<Paragraph>().firstOrNull;
    final otherChildren = allChildren.where((c) => c != firstParagraph).toList();

    final textAlign = firstParagraph?.textAlign ?? 'left';
    final mainAxisAlignment = switch (textAlign) {
      'center' => MainAxisAlignment.center,
      'right' => MainAxisAlignment.end,
      _ => MainAxisAlignment.start,
    };
    final useShrinkWrap = textAlign != 'left' && textAlign != 'justify';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── UPPER PART: Marker + First Paragraph ─────────────
          if (firstParagraph != null)
            Row(
            mainAxisAlignment: mainAxisAlignment,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ListMarker(
                node: widget.node,
                lineHeight: widget.document.pendingLineHeight,
                width: FluentListItemWidget._markerWidth,
                document: widget.document,
              ),
              if (useShrinkWrap)
                Flexible(
                  child: FluentParagraphWidget(
                    node: firstParagraph,
                    document: widget.document,
                    applyParagraphSpacing: false,
                    shrinkWrap: true,
                  ),
                )
              else
                Expanded(
                  child: FluentParagraphWidget(
                    node: firstParagraph,
                    document: widget.document,
                    applyParagraphSpacing: false,
                    shrinkWrap: false,
                  ),
                ),
            ],
          ),

        // ── LOWER PART: Other children ─
        if (otherChildren.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: otherChildren
                  .map((child) => buildFNodeWidget(child, widget.document))
                  .whereType<Widget>()
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Marker widget ────────────────────────────────────────────────────────────

class _ListMarker extends StatelessWidget {
  const _ListMarker({
    required this.node,
    this.lineHeight = 1.15,
    required this.width,
    required this.document,
  });

  final ListItem node;
  final double lineHeight;
  final double width;
  final FluentDocument document;

  @override
  Widget build(BuildContext context) {
    final String label = _resolveLabel();

    return SizedBox(
      // fixed width keeps all markers aligned regardless of digit count
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: GestureDetector(
          onTap: () => _handleMarkerLeftClick(context),
          onSecondaryTap: () => _showMarkerTypeDialog(context),
          onLongPress: () => _showMarkerTypeDialog(context),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(
              label,
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 14, 
                height: lineHeight, 
                color: Theme.of(context).colorScheme.onSurface,
                decoration: _isCheckboxType(node.bulletType) 
                    ? TextDecoration.none 
                    : TextDecoration.underline,
                decorationColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                decorationStyle: TextDecorationStyle.dotted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleMarkerLeftClick(BuildContext context) {
    if (_isCheckboxType(node.bulletType)) {
      // Toggle checkbox state
      _toggleCheckboxState();
    }
  }

  void _toggleCheckboxState() {
    // Cycle through checkbox states: checkbox -> checkbox-checked -> checkbox-crossed -> checkbox
    switch (node.bulletType) {
      case 'checkbox':
        node.bulletType = 'checkbox-checked';
        break;
      case 'checkbox-checked':
        node.bulletType = 'checkbox-crossed';
        break;
      case 'checkbox-crossed':
        node.bulletType = 'checkbox';
        break;
      default:
        node.bulletType = 'checkbox';
        break;
    }
    document.updateContent();
  }

  void _showMarkerTypeDialog(BuildContext context) {
    showListMarkerDialog(
      context,
      node.bulletType,
      (newMarkerType) {
        // Update the marker type for this list item and all items at the same level
        _updateMarkerTypeForList(newMarkerType);
      },
    );
  }

  void _updateMarkerTypeForList(String newMarkerType) {
    // Find the parent FluentList and update all its ListItems
    final parentList = _findParentFluentList(node);
    if (parentList != null) {
      // Check if we're dealing with checkboxes
      if (_isCheckboxType(newMarkerType)) {
        // For checkboxes, only update non-checkbox items or convert to base checkbox
        for (final item in parentList.items) {
          if (!_isCheckboxType(item.bulletType)) {
            // Convert non-checkbox items to base checkbox type
            item.bulletType = 'checkbox';
          }
          // If already a checkbox, preserve its current state
        }
      } else {
        // For non-checkbox types, update all items consistently
        for (final item in parentList.items) {
          item.bulletType = newMarkerType;
        }
      }
    } else {
      // Fallback: update only the current item
      node.bulletType = newMarkerType;
    }
    document.updateContent();
  }

  bool _isCheckboxType(String bulletType) {
    return bulletType == 'checkbox' || 
           bulletType == 'checkbox-checked' || 
           bulletType == 'checkbox-crossed';
  }

  FluentList? _findParentFluentList(ListItem listItem) {
    // Find the parent FluentList by traversing the document structure
    return _findFluentListInNode(document.content, listItem);
  }

  FluentList? _findFluentListInNode(FNode node, ListItem targetListItem) {
    // Check if this node is a FluentList containing our target
    if (node is FluentList) {
      if (node.items.contains(targetListItem)) {
        return node;
      }
    }
    
    // Recursively search in children
    if (node is InlineContainerNode) {
      final container = node as InlineContainerNode;
      for (final child in container.getChildren()) {
        final result = _findFluentListInNode(child, targetListItem);
        if (result != null) {
          return result;
        }
      }
    }
    
    return null;
  }

  String _resolveLabel() {
    final listType = node.bulletType;
    final depth = node.indexList.length; // nesting level (0-based)
    final index = node.indexList.last; // 1-based

    switch (listType) {
      case 'ordered':
        return '$index.';
      case 'ordered-parenthesis':
        return '$index)';
      case 'ordered-alpha':
        return '${_toAlpha(index)}.';
      case 'ordered-alpha-parenthesis':
        return '${_toAlpha(index)})';
      case 'ordered-alpha-upper':
        return '${_toAlphaUpper(index)}.';
      case 'ordered-alpha-upper-parenthesis':
        return '${_toAlphaUpper(index)})';
      case 'ordered-roman':
        return '${_toRoman(index)}.';
      case 'ordered-roman-parenthesis':
        return '${_toRoman(index)})';
      case 'ordered-roman-upper':
        return '${_toRomanUpper(index)}.';
      case 'ordered-roman-upper-parenthesis':
        return '${_toRomanUpper(index)})';
      case 'bullet':
        const bullets = ['•', '◦', '▪'];
        return bullets[depth % bullets.length];
      case 'bullet-circle':
        const circles = ['○', '◦', '●'];
        return circles[depth % circles.length];
      case 'bullet-square':
        const squares = ['□', '▫', '■'];
        return squares[depth % squares.length];
      case 'checkbox':
        return '☐';
      case 'checkbox-checked':
        return '☑';
      case 'checkbox-crossed':
        return '☒';
      default:
        // Fallback to bullet
        const bullets = ['•', '◦', '▪'];
        return bullets[depth % bullets.length];
    }
  }

  String _toAlpha(int number) {
    return String.fromCharCode(96 + number); // a, b, c, ...
  }

  String _toAlphaUpper(int number) {
    return String.fromCharCode(64 + number); // A, B, C, ...
  }

  String _toRoman(int number) {
    if (number <= 0 || number > 3999) return number.toString();
    final values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
    final symbols = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I'];
    String result = '';
    for (int i = 0; i < values.length; i++) {
      while (number >= values[i]) {
        number -= values[i];
        result += symbols[i];
      }
    }
    return result.toLowerCase();
  }

  String _toRomanUpper(int number) {
    return _toRoman(number).toUpperCase();
  }

}
