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
    final liveNode = (findById(widget.document.content, widget.node.id) as ListItem?) ?? widget.node;
    final allChildren = liveNode.getChildren();

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
    String? oldMarkerType;
    bool isAddition = false;
    bool isDeletion = false;
    for (final plugin in document.registry.plugins) {
      if (plugin.runtimeType.toString() == 'FluentSuggestionPlugin') {
        dynamic p = plugin;
        if (p.controller != null) {
          oldMarkerType = p.controller.getOldMarkerTypeForNode(node.id);
          try {
            isAddition = p.controller.isListItemAddition(node);
          } catch (_) {}
          try {
            isDeletion = p.controller.isListItemDeletion(node);
          } catch (_) {}
        }
      }
    }

    final String label = _resolveLabel();

    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color addBg = isDark ? const Color(0x3581C784) : const Color(0x354CAF50);
    final Color delBg = isDark ? const Color(0x35EF9A9A) : const Color(0x35F44336);
    final Color delLineColor = isDark ? const Color(0xFFEF5350) : const Color(0xFFE53935);
    final Color addTextColor = isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
    final Color delTextColor = isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F);

    Widget labelChild;
    if (oldMarkerType != null && oldMarkerType != node.bulletType) {
      final oldLabel = _resolveLabelForType(oldMarkerType);
      labelChild = RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$oldLabel ',
              style: TextStyle(
                fontSize: 14,
                height: lineHeight,
                color: delTextColor,
                backgroundColor: delBg,
                decoration: TextDecoration.lineThrough,
                decorationColor: delLineColor,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 14,
                height: lineHeight,
                color: addTextColor,
                backgroundColor: addBg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (isAddition) {
      labelChild = Text(
        label,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: 14, 
          height: lineHeight, 
          color: addTextColor,
          backgroundColor: addBg,
          fontWeight: FontWeight.bold,
        ),
      );
    } else if (isDeletion) {
      labelChild = Text(
        label,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: 14, 
          height: lineHeight, 
          color: delTextColor,
          backgroundColor: delBg,
          decoration: TextDecoration.lineThrough,
          decorationColor: delLineColor,
        ),
      );
    } else {
      labelChild = Text(
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
      );
    }

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
            child: labelChild,
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
    for (final plugin in document.registry.plugins) {
      if (plugin.runtimeType.toString() == 'FluentSuggestionPlugin') {
        dynamic p = plugin;
        if (p.controller != null && p.controller.mode.toString() == 'FluentSuggestionMode.suggesting') {
          final nextState = switch (node.bulletType) {
            'checkbox' => 'checkbox-checked',
            'checkbox-checked' => 'checkbox-crossed',
            'checkbox-crossed' => 'checkbox',
            _ => 'checkbox-checked',
          };
          p.controller.handleSuggestedListMarkChange(document, node, nextState);
          return;
        }
      }
    }

    document.saveState(description: 'Toggle checkbox state', forceNewAction: true);
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
    for (final plugin in document.registry.plugins) {
      if (plugin.runtimeType.toString() == 'FluentSuggestionPlugin') {
        dynamic p = plugin;
        if (p.controller != null && p.controller.mode.toString() == 'FluentSuggestionMode.suggesting') {
          p.controller.handleSuggestedListMarkChange(document, node, newMarkerType);
          return;
        }
      }
    }

    document.saveState(description: 'Change list marker', forceNewAction: true);
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

  String _resolveLabel() => _resolveLabelForType(node.bulletType);

  String _resolveLabelForType(String listType) {
    final depth = node.indexList.isNotEmpty ? node.indexList.length : 1;
    final index = node.indexList.isNotEmpty ? node.indexList.last : 1;

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
