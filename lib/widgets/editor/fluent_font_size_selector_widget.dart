import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/fragment_operations.dart';
import 'package:fluent_editor/utils/node_operations.dart';
import 'package:fluent_editor/utils/resolve_selection.dart';
import 'package:flutter/material.dart';

const _fontSizes = <int>[
  8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 32, 36, 48, 72
];

class FluentFontSizeSelectorWidget extends StatefulWidget {
  final FluentDocument document;

  const FluentFontSizeSelectorWidget({super.key, required this.document});

  @override
  State<FluentFontSizeSelectorWidget> createState() => _FluentFontSizeSelectorWidgetState();
}

class _FluentFontSizeSelectorWidgetState extends State<FluentFontSizeSelectorWidget> {
  int _currentSize = 14;

  @override
  void initState() {
    super.initState();
    widget.document.addListener(_onDocumentChanged);
    _updateSize();
  }

  @override
  void didUpdateWidget(covariant FluentFontSizeSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
      _updateSize();
    }
  }

  @override
  void dispose() {
    widget.document.removeListener(_onDocumentChanged);
    super.dispose();
  }

  void _onDocumentChanged() => _updateSize();

  void _updateSize() {
    final size = _resolveCurrentSize();
    if (size != _currentSize) {
      setState(() => _currentSize = size);
    }
  }

  int _resolveCurrentSize() {
    final document = widget.document;
    final cursor = document.cursor;
    final root = document.content;

    if (cursor.anchorId != cursor.focusId || cursor.anchorOffset != cursor.focusOffset) {
      final selection = resolveSelection(
        root,
        cursor.anchorId,
        cursor.anchorOffset,
        cursor.focusId,
        cursor.focusOffset,
      );
      if (selection != null) {
        final sizes = <double?>{};
        for (final node in selection.nodes) {
          final leaves = FragmentOperations.collectLeafFragments(node.container as FNode);
          bool inRange = false;
          for (final leaf in leaves) {
            if (leaf.id == node.startFragment.id) inRange = true;
            if (inRange && leaf is! FluentImage) {
              sizes.add(leaf.fontSize);
            }
            if (leaf.id == node.endFragment.id) inRange = false;
          }
        }
        if (sizes.length == 1) {
          final single = sizes.single;
          if (single != null) return single.round();
        }
        return 14;
      }
    }

    final frag = findById(root, cursor.anchorId);
    if (frag is Fragment) {
      return frag.fontSize.round();
    }
    return document.pendingFontSize.round();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final displaySize = _fontSizes.contains(_currentSize)
        ? _currentSize
        : _fontSizes.reduce((a, b) =>
            (_currentSize - a).abs() < (_currentSize - b).abs() ? a : b);

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
          child: DropdownButton<int>(
            value: displaySize,
            isDense: true,
            icon: const Icon(Icons.arrow_drop_down, size: 18),
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
            selectedItemBuilder: (context) {
              return _fontSizes.map((size) {
                return Center(
                  child: Text(
                    '$_currentSize',
                    style: const TextStyle(fontSize: 13),
                  ),
                );
              }).toList();
            },
            items: _fontSizes.map((int size) {
              return DropdownMenuItem<int>(
                value: size,
                child: Text(
                  '$size',
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (int? newValue) {
              if (newValue != null) {
                widget.document.eventHandler.handleFontSize(newValue.toDouble());
                widget.document.requestEditorFocus();
              }
            },
          ),
        ),
      ),
    );
  }
}