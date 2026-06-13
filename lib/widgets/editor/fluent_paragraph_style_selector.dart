import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/styles.dart';
import 'package:flutter/material.dart';

class FluentParagraphStyleSelector extends StatefulWidget {
  final FluentDocument document;

  const FluentParagraphStyleSelector({super.key, required this.document});

  @override
  State<FluentParagraphStyleSelector> createState() =>
      _FluentParagraphStyleSelectorState();
}

class _FluentParagraphStyleSelectorState
    extends State<FluentParagraphStyleSelector> {
  ParagraphStyle _currentStyle = ParagraphStyle.normal;

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
    _updateStyle();
  }

  @override
  void didUpdateWidget(covariant FluentParagraphStyleSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
      _updateStyle();
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() => _updateStyle();

  void _updateStyle() {
    final style = widget.document.pendingStyle;
    if (style.name != _currentStyle.name) {
      setState(() => _currentStyle = style);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(100),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: colorScheme.outline.withAlpha(100)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<ParagraphStyle>(
            value: _currentStyle,
            isDense: true,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
            selectedItemBuilder: (context) {
              return ParagraphStyle.predefinedStyles.map((style) {
                return Center(
                  child: Text(
                    _currentStyle.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }).toList();
            },
            items: ParagraphStyle.predefinedStyles.map((style) {
              return DropdownMenuItem<ParagraphStyle>(
                value: style,
                child: Text(
                  style.displayName,
                  style: TextStyle(
                    fontFamily: style.fontFamily,
                    fontSize: style.fontSize ?? 14,
                    fontWeight: style.styles?.contains('bold') == true
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontStyle: style.styles?.contains('italic') == true
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              );
            }).toList(),
            onChanged: (ParagraphStyle? newStyle) {
              if (newStyle != null) {
                widget.document.eventHandler.handleParagraphStyle(newStyle);
                widget.document.requestEditorFocus();
              }
            },
          ),
        ),
      ),
    );
  }
}