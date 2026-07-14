import 'package:flutter/material.dart';

import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/widgets/editor/fluent_formatting_bar.dart';

/// Floating bubble toolbar that appears above the current text selection.
/// Visible only when the selection is non-collapsed.
///
/// Requires a [stackKey] whose RenderBox is used to convert the caret's
/// global screen rect into local coordinates for positioning.
class FluentBubbleToolbar extends StatefulWidget {
  const FluentBubbleToolbar({
    super.key,
    required this.document,
    required this.stackKey,
    this.labels,
    this.scrollController,
  });

  final FluentDocument document;
  final GlobalKey stackKey;
  final FluentEditorLabels? labels;
  final ScrollController? scrollController;

  @override
  State<FluentBubbleToolbar> createState() => _FluentBubbleToolbarState();
}

class _FluentBubbleToolbarState extends State<FluentBubbleToolbar> {
  Offset? _bubblePosition;
  bool _visible = false;
  Size _stackSize = Size.zero;

  static const double _bubbleHeight = 48.0;

  @override
  void initState() {
    super.initState();
    widget.document.cursor.addListener(_onCursorChanged);
    widget.document.addListener(_onDocumentChanged);
    widget.scrollController?.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant FluentBubbleToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      oldWidget.document.cursor.removeListener(_onCursorChanged);
      widget.document.cursor.addListener(_onCursorChanged);
      oldWidget.document.removeListener(_onDocumentChanged);
      widget.document.addListener(_onDocumentChanged);
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.document.cursor.removeListener(_onCursorChanged);
    widget.document.removeListener(_onDocumentChanged);
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  ScrollController? get scrollController => widget.scrollController;

  void _onCursorChanged() => _updatePosition();

  void _onDocumentChanged() {
    if (widget.document.cursorOnlyChange) return;
    _updatePosition();
  }

  void _onScroll() {
    if (!mounted) return;
    if (widget.document.cursor.isCollapsed) return;
    _updatePosition();
  }

  void _updatePosition() {
    final cursor = widget.document.cursor;
    if (cursor.isCollapsed) {
      if (_visible) setState(() => _visible = false);
      return;
    }

    // Defer to post-frame so render objects are up-to-date after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _computePosition();
    });
  }

  void _computePosition() {
    final cursor = widget.document.cursor;
    if (cursor.isCollapsed) {
      if (_visible) setState(() => _visible = false);
      return;
    }

    final fragId =
        cursor.focusId.isNotEmpty ? cursor.focusId : cursor.anchorId;
    final offset =
        cursor.focusId.isNotEmpty ? cursor.focusOffset : cursor.anchorOffset;

    final rect =
        widget.document.paragraphRegistry.resolveCaretScreenRect(fragId, offset);
    if (rect == null) {
      if (_visible) setState(() => _visible = false);
      return;
    }

    final stackBox = widget.stackKey.currentContext?.findRenderObject();
    if (stackBox is! RenderBox || !stackBox.hasSize) {
      if (_visible) setState(() => _visible = false);
      return;
    }

    final localTopLeft = stackBox.globalToLocal(rect.topLeft);
    _stackSize = stackBox.size;
    final stackSize = _stackSize;

    // Position the bubble above the selection, centered horizontally.
    const bubbleHeight = _bubbleHeight;
    const bubbleGap = 12.0;
    double top = localTopLeft.dy - bubbleHeight - bubbleGap;

    // Clamp vertically: if not enough space above, show below the selection.
    if (top < 4.0) {
      top = localTopLeft.dy + rect.height + bubbleGap;
    }
    // Clamp within stack bounds.
    top = top.clamp(4.0, stackSize.height - bubbleHeight - 4.0);

    // Center horizontally on the caret.
    double left = localTopLeft.dx - 200; // approximate half bubble width
    left = left.clamp(4.0, stackSize.width - 4.0);

    setState(() {
      _bubblePosition = Offset(left, top);
      _visible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _bubblePosition == null) return const SizedBox.shrink();

    return Positioned(
      left: _bubblePosition!.dx,
      top: _bubblePosition!.dy,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.3),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _stackSize.width - 16,
            maxHeight: _bubbleHeight,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: FluentFormattingBar(
              document: widget.document,
              labels: widget.labels,
              compact: true,
            ),
          ),
        ),
      ),
    );
  }
}
