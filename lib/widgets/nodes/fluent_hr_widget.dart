import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/cursor_navigation.dart';
import 'package:flutter/material.dart';

class FluentHrWidget extends StatefulWidget {
  const FluentHrWidget({
    super.key,
    required this.node,
    required this.document,
  });

  final HorizontalRule node;
  final FluentDocument document;

  @override
  State<FluentHrWidget> createState() => _FluentHrWidgetState();
}

class _FluentHrWidgetState extends State<FluentHrWidget> {
  RenderBox? _renderBox;

  @override
  void initState() {
    super.initState();
    widget.document.cursor.addListener(_rebuild);
    widget.document.selectionManager.addListener(_rebuild);
    widget.document.addListener(_rebuild);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _renderBox = context.findRenderObject() as RenderBox?;
      if (_renderBox != null) {
        widget.document.paragraphRegistry.registerHR(widget.node.id, _renderBox!);
      }
    });
  }

  @override
  void didUpdateWidget(FluentHrWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.cursor != widget.document.cursor) {
      oldWidget.document.cursor.removeListener(_rebuild);
      widget.document.cursor.addListener(_rebuild);
    }
    if (oldWidget.document.selectionManager != widget.document.selectionManager) {
      oldWidget.document.selectionManager.removeListener(_rebuild);
      widget.document.selectionManager.addListener(_rebuild);
    }
    if (oldWidget.document != widget.document) {
      oldWidget.document.removeListener(_rebuild);
      widget.document.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    if (_renderBox != null) {
      widget.document.paragraphRegistry.unregisterHR(widget.node.id, _renderBox!);
    }
    widget.document.cursor.removeListener(_rebuild);
    widget.document.selectionManager.removeListener(_rebuild);
    widget.document.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    // Skip rebuild if this node was not touched by the last document change.
    if (!widget.document.isNodeDirty(widget.node.id)) return;
    setState(() {});
  }

  void _onTapDown(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    final localX = box != null
        ? box.globalToLocal(details.globalPosition).dx
        : 0.0;
    final totalWidth = box?.size.width ?? 1.0;
    final offset = localX < totalWidth / 2 ? 0 : 1;
    widget.document.cursor.moveTo(widget.node.id, offset);
    widget.document.selectionManager.collapse();
    widget.document.updateContent();
  }

  @override
  Widget build(BuildContext context) {
    final cursor = widget.document.cursor;
    final node = widget.node;

    final cursorOnHr = cursor.isCollapsed && cursor.anchorId == node.id;
    final cursorBefore = cursorOnHr && cursor.anchorOffset == 0;
    final cursorAfter  = cursorOnHr && cursor.anchorOffset == 1;

    bool isSelected = false;
    if (!cursor.isCollapsed) {
      final stops = widget.document.caretStops;
      final anchorIdx = findStopIndex(stops, cursor.anchorId, cursor.anchorOffset);
      final focusIdx  = findStopIndex(stops, cursor.focusId,  cursor.focusOffset);
      final hr0Idx    = findStopIndex(stops, node.id, 0);
      final hr1Idx    = findStopIndex(stops, node.id, 1);
      if (anchorIdx >= 0 && focusIdx >= 0 && hr0Idx >= 0 && hr1Idx >= 0) {
        final lo = anchorIdx < focusIdx ? anchorIdx : focusIdx;
        final hi = anchorIdx < focusIdx ? focusIdx  : anchorIdx;
        isSelected = lo <= hr0Idx && hr1Idx <= hi;
      }
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                  : null,
              borderRadius: BorderRadius.circular(2),
            ),
            child: const Divider(thickness: 2, height: 18),
          ),
          if (cursorBefore)
            const Positioned(left: 0, top: 0, bottom: 0, child: _CaretLine()),
          if (cursorAfter)
            const Positioned(right: 0, top: 0, bottom: 0, child: _CaretLine()),
        ],
      ),
    );
  }
}

class _CaretLine extends StatelessWidget {
  const _CaretLine();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 2,
        child: ColoredBox(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
