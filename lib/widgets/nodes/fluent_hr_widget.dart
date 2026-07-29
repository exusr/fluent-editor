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
    if (!widget.document.isNodeDirty(widget.node.id)) return;
    setState(() {});
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.document.imeHandler.isComposing) {
      widget.document.imeHandler.commitIfComposing();
    }
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

    final isSelected = isNodeInSelectionRange(widget.document.caretStops, cursor, node.id);

    final isDeletion = node.styles?.contains('suggestion_deletion') == true ||
        node.styles?.contains('strikethrough') == true;
    final isAddition = node.styles?.contains('suggestion_addition') == true;

    final bgTint = isDeletion
        ? const Color(0x40F44336)
        : (isAddition
            ? const Color(0x404CAF50)
            : (isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)
                : null));

    final hrColor = isDeletion
        ? const Color(0xFFEF5350)
        : (isAddition
            ? const Color(0xFF66BB6A)
            : null);

    return GestureDetector(
      onTapDown: _onTapDown,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: bgTint,
              borderRadius: BorderRadius.circular(4),
              border: isDeletion
                  ? Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.5), width: 1)
                  : isAddition
                      ? Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.5), width: 1)
                      : null,
            ),
            child: Divider(
              thickness: 2,
              height: 18,
              color: hrColor ?? Theme.of(context).dividerColor,
            ),
          ),
          if (isDeletion)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
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
