import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/widgets/node_widget_builder.dart';
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
  int _lastContentVersion = -1;

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

  void _onStateChange() {
    if (widget.document.cursorOnlyChange) return;
    if (!widget.document.isNodeDirty(widget.node.id)) return;
    final version = widget.document.contentVersion;
    if (version == _lastContentVersion) return;
    _lastContentVersion = version;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final allChildren = widget.node.getChildren();

    int firstParagraphIndex = -1;
    for (int i = 0; i < allChildren.length; i++) {
      if (allChildren[i] is Paragraph) {
        firstParagraphIndex = i;
        break;
      }
    }
    final firstParagraph = firstParagraphIndex >= 0
        ? allChildren[firstParagraphIndex] as Paragraph
        : null;

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

        if (allChildren.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < allChildren.length; i++)
                  if (i != firstParagraphIndex)
                    buildFNodeWidget(allChildren[i], widget.document),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
      _toggleCheckboxState();
    }
  }

  void _toggleCheckboxState() {
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
        _updateMarkerTypeForList(newMarkerType);
      },
    );
  }

  void _updateMarkerTypeForList(String newMarkerType) {
    final parentList = _findParentFluentList(node);
    if (parentList != null) {
      if (_isCheckboxType(newMarkerType)) {
        for (final item in parentList.items) {
          if (!_isCheckboxType(item.bulletType)) {
            item.bulletType = 'checkbox';
          }
        }
      } else {
        for (final item in parentList.items) {
          item.bulletType = newMarkerType;
        }
      }
    } else {
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
    return findAncestorCached<FluentList>(document, listItem);
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
        const bullets = ['•', '◦', '▪'];
        return bullets[depth % bullets.length];
    }
  }

  String _toAlpha(int number) {
    return String.fromCharCode(96 + number);
  }

  String _toAlphaUpper(int number) {
    return String.fromCharCode(64 + number);
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
