import 'package:flutter/material.dart';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/styles.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/cursor_utils.dart';
import 'package:fluent_editor/utils/color_utils.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import 'package:fluent_editor/widgets/editor/fluent_font_selector_widget.dart';
import 'package:fluent_editor/widgets/editor/fluent_font_size_selector_widget.dart';
import 'package:fluent_editor/widgets/editor/fluent_paragraph_style_selector.dart';
import 'package:fluent_editor/widgets/editor/fluent_paragraph_spacing_button.dart';
import 'package:fluent_editor/widgets/editor/fluent_color_button.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Reusable formatting bar with all the inline formatting buttons
/// (bold, italic, colors, alignment, lists, etc.).
/// Used by both [FluentToolbar] (fixed mode) and [FluentBubbleToolbar].
class FluentFormattingBar extends StatefulWidget {
  const FluentFormattingBar({
    super.key,
    required this.document,
    this.labels,
    this.compact = false,
  });

  final FluentDocument document;
  final FluentEditorLabels? labels;

  /// When true, renders buttons in a single horizontal [Row] (no wrapping).
  /// Intended for the bubble toolbar where vertical space is limited.
  final bool compact;

  @override
  State<FluentFormattingBar> createState() => _FluentFormattingBarState();
}

class _FluentFormattingBarState extends State<FluentFormattingBar> {
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  bool _isStrikethrough = false;
  bool _isSmallCaps = false;
  bool _isSuperscript = false;
  bool _isSubscript = false;
  TextAlign _textAlign = TextAlign.left;

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
    widget.document.cursor.addListener(_onCursorChanged);
    _updateFormats();
  }

  @override
  void didUpdateWidget(covariant FluentFormattingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
      oldWidget.document.cursor.removeListener(_onCursorChanged);
      widget.document.cursor.addListener(_onCursorChanged);
      _updateFormats();
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChanged);
    widget.document.cursor.removeListener(_onCursorChanged);
    super.dispose();
  }

  void _onDocumentChanged() {
    if (widget.document.cursorOnlyChange) return;
    _updateFormats();
  }

  void _onCursorChanged() => _updateFormats();

  void _updateFormats() {
    final cursor = widget.document.cursor;
    final pendingStyles = widget.document.pendingStyles;

    if (cursor.isCollapsed) {
      final newBold = pendingStyles.contains('bold');
      final newItalic = pendingStyles.contains('italic');
      final newUnderline = pendingStyles.contains('underline');
      final newStrikethrough = pendingStyles.contains('strikethrough');
      final newSmallCaps = pendingStyles.contains('smallcaps');
      final newSuperscript = pendingStyles.contains('superscript');
      final newSubscript = pendingStyles.contains('subscript');
      final newTextAlign = _resolveTextAlign();

      if (newBold != _isBold || newItalic != _isItalic ||
          newUnderline != _isUnderline ||
          newStrikethrough != _isStrikethrough ||
          newSmallCaps != _isSmallCaps ||
          newSuperscript != _isSuperscript ||
          newSubscript != _isSubscript || newTextAlign != _textAlign) {
        setState(() {
          _isBold = newBold;
          _isItalic = newItalic;
          _isUnderline = newUnderline;
          _isStrikethrough = newStrikethrough;
          _isSmallCaps = newSmallCaps;
          _isSuperscript = newSuperscript;
          _isSubscript = newSubscript;
          _textAlign = newTextAlign;
        });
      }
      return;
    }

    final selection = resolveSelectionFromCursor(widget.document);
    final allLeaves = <Fragment>[];
    if (selection != null) {
      for (final node in selection.nodes) {
        allLeaves.addAll(FragmentOperations.collectLeavesInRange(node));
      }
    }

    bool hasStyle(String name) =>
        allLeaves.any((leaf) => leaf.styles?.contains(name) ?? false);

    final newBold = hasStyle('bold');
    final newItalic = hasStyle('italic');
    final newUnderline = hasStyle('underline');
    final newStrikethrough = hasStyle('strikethrough');
    final newSmallCaps = hasStyle('smallcaps');
    final newSuperscript = hasStyle('superscript');
    final newSubscript = hasStyle('subscript');
    final newTextAlign = _resolveTextAlign();

    if (newBold != _isBold || newItalic != _isItalic ||
        newUnderline != _isUnderline ||
        newStrikethrough != _isStrikethrough ||
        newSmallCaps != _isSmallCaps ||
        newSuperscript != _isSuperscript ||
        newSubscript != _isSubscript || newTextAlign != _textAlign) {
      setState(() {
        _isBold = newBold;
        _isItalic = newItalic;
        _isUnderline = newUnderline;
        _isStrikethrough = newStrikethrough;
        _isSmallCaps = newSmallCaps;
        _isSuperscript = newSuperscript;
        _isSubscript = newSubscript;
        _textAlign = newTextAlign;
      });
    }
  }

  TextAlign _resolveTextAlign() {
    final containerId = widget.document
        .findLogicalContainerId(widget.document.cursor.anchorId);
    if (containerId == null) return TextAlign.left;
    final container = widget.document.nodeById(containerId);
    if (container is Paragraph) return parseTextAlign(container.textAlign);
    if (container is FluentImage) return parseTextAlign(container.textAlign);
    return TextAlign.left;
  }

  Widget _buildAlignButton(IconData icon, TextAlign align, String tooltip) {
    final isActive = _textAlign == align;
    return _buildToolbarButton(
      icon: icon,
      tooltip: tooltip,
      iconColor: isActive ? Theme.of(context).colorScheme.primary : null,
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primaryContainer.withAlpha(180)
          : null,
      onPressed: () {
        widget.document.eventHandler
            .handleTextAlign(serializeTextAlign(align));
        widget.document.requestEditorFocus();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _buildCompactChildren(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: _buildFullChildren(),
      ),
    );
  }

  List<Widget> _buildFullChildren() {
    return <Widget>[
      FluentParagraphStyleSelector(document: widget.document),
      const SizedBox(width: 4),
      FluentFontSelectorWidget(document: widget.document),
      const SizedBox(width: 4),
      FluentFontSizeSelectorWidget(document: widget.document),
      _buildVerticalDivider(),
      _buildFormatButton(
        icon: Icons.format_bold,
        tooltip: "Bold (Ctrl+B)",
        isActive: _isBold,
        handler: widget.document.eventHandler.handleBold,
      ),
      _buildFormatButton(
        icon: Icons.format_italic,
        tooltip: "Italic (Ctrl+I)",
        isActive: _isItalic,
        handler: widget.document.eventHandler.handleItalic,
      ),
      _buildFormatButton(
        icon: Icons.format_underline,
        tooltip: "Underline (Ctrl+U)",
        isActive: _isUnderline,
        handler: widget.document.eventHandler.handleUnderline,
      ),
      FluentColorButton(
        document: widget.document,
        labels: widget.labels,
        title: widget.labels?.textColor ?? 'Text color',
        noneLabel: 'Auto',
        presets: presetColors,
        saveStateDescription: 'Text color',
        defaultCustomColor: Colors.black,
        customDialogTitle: 'Custom color',
        icon: Icons.format_color_text,
        resolveColor: (doc) => doc.pendingColor,
        handleColor: (c) =>
            widget.document.eventHandler.handleTextColor(c),
      ),
      FluentColorButton(
        document: widget.document,
        labels: widget.labels,
        title: widget.labels?.highlightColor ?? 'Highlight',
        noneLabel: 'None',
        presets: presetHighlightColors,
        saveStateDescription: 'Highlight color',
        defaultCustomColor: const Color(0xFFFFFF00),
        customDialogTitle: 'Custom highlight color',
        icon: Icons.border_color,
        resolveColor: (doc) => doc.pendingHighlightColor,
        handleColor: (c) =>
            widget.document.eventHandler.handleHighlightColor(c),
      ),
      _buildVerticalDivider(),
      _buildToolbarButton(
        icon: Icons.link,
        tooltip: "Insert Link",
        onPressed: () {
          widget.document.dialogPresenter.handleInsertLink(context);
          widget.document.requestEditorFocus();
        },
      ),
      _buildToolbarButton(
        icon: Icons.format_list_bulleted,
        tooltip: "Insert Bullet List",
        onPressed: () {
          widget.document.eventHandler
              .handleInsertNode('list', {'listType': 'bullet'});
          widget.document.requestEditorFocus();
        },
      ),
      _buildToolbarButton(
        icon: Icons.format_list_numbered,
        tooltip: "Insert Numbered List",
        onPressed: () {
          widget.document.eventHandler
              .handleInsertNode('list', {'listType': 'ordered'});
          widget.document.requestEditorFocus();
        },
      ),
      _buildToolbarButton(
        icon: Icons.format_clear,
        tooltip: "Clear formatting",
        onPressed: () {
          widget.document.eventHandler.handleClearFormatting();
          widget.document.requestEditorFocus();
        },
      ),
      _buildVerticalDivider(),
      _buildAlignButton(Icons.format_align_left, TextAlign.left, 'Align left'),
      _buildAlignButton(Icons.format_align_center, TextAlign.center, 'Align center'),
      _buildAlignButton(Icons.format_align_right, TextAlign.right, 'Align right'),
      _buildAlignButton(Icons.format_align_justify, TextAlign.justify, 'Justify'),
      _buildVerticalDivider(),
      _buildToolbarButton(
        icon: Icons.format_indent_increase,
        tooltip: "Indent (Tab)",
        onPressed: () {
          widget.document.eventHandler.handleTab();
          widget.document.requestEditorFocus();
        },
      ),
      _buildToolbarButton(
        icon: Icons.format_indent_decrease,
        tooltip: "Outdent (Shift+Tab)",
        onPressed: () {
          widget.document.eventHandler.handleShiftTab();
          widget.document.requestEditorFocus();
        },
      ),
      _buildVerticalDivider(),
      FluentParagraphSpacingButton(
          document: widget.document, labels: widget.labels),
    ];
  }

  List<Widget> _buildCompactChildren() {
    return <Widget>[
      _buildCompactStyleButton(),
      _buildCompactFontButton(),
      _buildCompactFontSizeButton(),
      _buildVerticalDivider(),
      _buildFormatButton(
        icon: Icons.format_bold,
        tooltip: "Bold (Ctrl+B)",
        isActive: _isBold,
        handler: widget.document.eventHandler.handleBold,
      ),
      _buildFormatButton(
        icon: Icons.format_italic,
        tooltip: "Italic (Ctrl+I)",
        isActive: _isItalic,
        handler: widget.document.eventHandler.handleItalic,
      ),
      _buildFormatButton(
        icon: Icons.format_underline,
        tooltip: "Underline (Ctrl+U)",
        isActive: _isUnderline,
        handler: widget.document.eventHandler.handleUnderline,
      ),
      FluentColorButton(
        document: widget.document,
        labels: widget.labels,
        title: widget.labels?.textColor ?? 'Text color',
        noneLabel: 'Auto',
        presets: presetColors,
        saveStateDescription: 'Text color',
        defaultCustomColor: Colors.black,
        customDialogTitle: 'Custom color',
        icon: Icons.format_color_text,
        resolveColor: (doc) => doc.pendingColor,
        handleColor: (c) =>
            widget.document.eventHandler.handleTextColor(c),
      ),
      FluentColorButton(
        document: widget.document,
        labels: widget.labels,
        title: widget.labels?.highlightColor ?? 'Highlight',
        noneLabel: 'None',
        presets: presetHighlightColors,
        saveStateDescription: 'Highlight color',
        defaultCustomColor: const Color(0xFFFFFF00),
        customDialogTitle: 'Custom highlight color',
        icon: Icons.border_color,
        resolveColor: (doc) => doc.pendingHighlightColor,
        handleColor: (c) =>
            widget.document.eventHandler.handleHighlightColor(c),
      ),
      _buildVerticalDivider(),
      _buildToolbarButton(
        icon: Icons.link,
        tooltip: "Insert Link",
        onPressed: () {
          widget.document.dialogPresenter.handleInsertLink(context);
          widget.document.requestEditorFocus();
        },
      ),
      _buildToolbarButton(
        icon: Icons.format_list_bulleted,
        tooltip: "Insert Bullet List",
        onPressed: () {
          widget.document.eventHandler
              .handleInsertNode('list', {'listType': 'bullet'});
          widget.document.requestEditorFocus();
        },
      ),
      _buildToolbarButton(
        icon: Icons.format_list_numbered,
        tooltip: "Insert Numbered List",
        onPressed: () {
          widget.document.eventHandler
              .handleInsertNode('list', {'listType': 'ordered'});
          widget.document.requestEditorFocus();
        },
      ),
      _buildToolbarButton(
        icon: Icons.format_clear,
        tooltip: "Clear formatting",
        onPressed: () {
          widget.document.eventHandler.handleClearFormatting();
          widget.document.requestEditorFocus();
        },
      ),
      _buildVerticalDivider(),
      _buildCompactAlignButton(),
      _buildCompactIndentButton(),
      _buildVerticalDivider(),
      FluentParagraphSpacingButton(
          document: widget.document, labels: widget.labels),
    ];
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    Color? iconColor,
    Color? backgroundColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          mouseCursor: onPressed != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildFormatButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback handler,
  }) {
    return _buildToolbarButton(
      icon: icon,
      tooltip: tooltip,
      iconColor: isActive ? Theme.of(context).colorScheme.primary : null,
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primaryContainer.withAlpha(180)
          : null,
      onPressed: () {
        handler();
        widget.document.requestEditorFocus();
      },
    );
  }

  IconData _alignIcon(TextAlign align) => switch (align) {
    TextAlign.left => Icons.format_align_left,
    TextAlign.center => Icons.format_align_center,
    TextAlign.right => Icons.format_align_right,
    TextAlign.justify => Icons.format_align_justify,
    _ => Icons.format_align_left,
  };

  Widget _buildCompactStyleButton() {
    return PopupMenuButton<ParagraphStyle>(
      tooltip: 'Paragraph style',
      icon: const Icon(Icons.text_fields, size: 20),
      padding: const EdgeInsets.all(8),
      onSelected: (style) {
        widget.document.eventHandler.handleParagraphStyle(style);
        widget.document.requestEditorFocus();
      },
      itemBuilder: (context) => ParagraphStyle.predefinedStyles.map((style) {
        return PopupMenuItem<ParagraphStyle>(
          value: style,
          child: Text(
            style.displayName,
            style: TextStyle(
              fontFamily: style.fontFamily,
              fontSize: (style.fontSize ?? 14).clamp(12.0, 18.0),
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
    );
  }

  Widget _buildCompactFontButton() {
    return PopupMenuButton<String>(
      tooltip: 'Font family',
      icon: const Icon(Icons.font_download, size: 20),
      padding: const EdgeInsets.all(8),
      onSelected: (font) {
        widget.document.eventHandler.handleFontFamily(font);
        widget.document.requestEditorFocus();
      },
      itemBuilder: (context) {
        final fonts = kIsWeb
            ? const ['DejaVu Sans', 'Crimson Text', 'Fira Sans', 'Lato',
              'Poppins', 'Titillium Web']
            : const ['DejaVu Sans', 'Calibri', 'Cambria', 'Comic Sans MS',
              'Courier New', 'Georgia', 'Helvetica', 'Impact', 'Lato',
              'Poppins', 'Tahoma', 'Times New Roman', 'Trebuchet MS',
              'Verdana'];
        return fonts.map((font) {
          return PopupMenuItem<String>(
            value: font,
            child: Text(font, style: TextStyle(fontFamily: font, fontSize: 14)),
          );
        }).toList();
      },
    );
  }

  Widget _buildCompactFontSizeButton() {
    const sizes = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 48, 72];
    return PopupMenuButton<int>(
      tooltip: 'Font size',
      icon: const Icon(Icons.format_size, size: 20),
      padding: const EdgeInsets.all(8),
      onSelected: (size) {
        widget.document.eventHandler.handleFontSize(size.toDouble());
        widget.document.requestEditorFocus();
      },
      itemBuilder: (context) => sizes.map((size) {
        return PopupMenuItem<int>(
          value: size,
          child: Text('$size'),
        );
      }).toList(),
    );
  }

  Widget _buildCompactAlignButton() {
    return PopupMenuButton<TextAlign>(
      tooltip: 'Alignment',
      icon: Icon(_alignIcon(_textAlign), size: 20),
      padding: const EdgeInsets.all(8),
      onSelected: (align) {
        widget.document.eventHandler
            .handleTextAlign(serializeTextAlign(align));
        widget.document.requestEditorFocus();
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: TextAlign.left, child: Row(children: [
          const Icon(Icons.format_align_left),
          const SizedBox(width: 8),
          Text(widget.labels?.alignLeft ?? 'Align left'),
        ])),
        PopupMenuItem(value: TextAlign.center, child: Row(children: [
          const Icon(Icons.format_align_center),
          const SizedBox(width: 8),
          Text(widget.labels?.alignCenter ?? 'Align center'),
        ])),
        PopupMenuItem(value: TextAlign.right, child: Row(children: [
          const Icon(Icons.format_align_right),
          const SizedBox(width: 8),
          Text(widget.labels?.alignRight ?? 'Align right'),
        ])),
        PopupMenuItem(value: TextAlign.justify, child: Row(children: [
          const Icon(Icons.format_align_justify),
          const SizedBox(width: 8),
          Text(widget.labels?.justify ?? 'Justify'),
        ])),
      ],
    );
  }

  Widget _buildCompactIndentButton() {
    return PopupMenuButton<String>(
      tooltip: 'Indentation',
      icon: const Icon(Icons.format_indent_increase, size: 20),
      padding: const EdgeInsets.all(8),
      onSelected: (action) {
        if (action == 'indent') {
          widget.document.eventHandler.handleTab();
        } else {
          widget.document.eventHandler.handleShiftTab();
        }
        widget.document.requestEditorFocus();
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'indent', child: Row(children: [
          const Icon(Icons.format_indent_increase),
          const SizedBox(width: 8),
          Text(widget.labels?.increaseIndent ?? 'Increase indent'),
        ])),
        PopupMenuItem(value: 'outdent', child: Row(children: [
          const Icon(Icons.format_indent_decrease),
          const SizedBox(width: 8),
          Text(widget.labels?.decreaseIndent ?? 'Decrease indent'),
        ])),
      ],
    );
  }
}
